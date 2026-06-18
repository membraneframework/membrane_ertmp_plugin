defmodule Membrane.ERTMP.Sink do
  @moduledoc """
  Membrane sink that publishes an audio/video stream to an RTMP(S) server
  using Enhanced RTMP (E-RTMP), backed by the Rust `rtmp` crate from
  software-mansion/smelter.

  ## Pads

  Both pads are **dynamic** (`:on_request`) so that the element can later
  accept multiple video renditions for IVS multitrack once the underlying
  crate gains multitrack support.  For a single-rendition stream connect
  exactly one `:video` pad and one `:audio` pad:

      child(:sink, %Membrane.ERTMP.Sink{host: "rtmp.example.com", ...})
      |> via_in(Pad.ref(:video, :main))
      ...
      |> via_in(Pad.ref(:audio, :main))
      ...

  ## Multitrack future path

  When the smelter `rtmp` crate adds multitrack E-RTMP support, each
  additional video rendition can be linked as another `:video` dynamic pad.
  The sink assigns monotonically increasing `TrackId` values to video pads
  in the order they are added, which maps directly to the E-RTMP multitrack
  track identifiers.  Audio pads similarly receive their own `TrackId`
  sequence (currently always 0 for a single audio track).

  ## Video format

  Accepts `%Membrane.H264{alignment: :au}` with AVCC stream structure
  `{:avc1, dcr}`.  The `dcr` binary (AVCDecoderConfigurationRecord) is sent
  as the RTMP VideoConfig before the first frame.  Annex-B H.264 is not
  supported; add `Membrane.H264.Parser` upstream with `output_stream_structure:
  :avc1` if needed.

  ## Audio format

  Accepts raw AAC frames (`%Membrane.AAC{encapsulation: :none}`) and raw Opus
  packets (`%Membrane.Opus{}`).  The first `handle_stream_format` call sends
  the appropriate AudioConfig (AudioSpecificConfig for AAC, OpusHead for Opus).
  """

  use Membrane.Sink

  require Membrane.Logger
  require Membrane.Pad, as: Pad

  alias Membrane.{AAC, H264, Opus}
  alias Membrane.ERTMP.Native
  alias Membrane.Buffer

  # ---------------------------------------------------------------------------
  # Options
  # ---------------------------------------------------------------------------

  def_options(
    host: [
      spec: String.t(),
      description: "RTMP server hostname or IP address"
    ],
    port: [
      spec: 1..65_535,
      description: "RTMP server port",
      default: 1935
    ],
    app: [
      spec: String.t(),
      description: "RTMP application name (e.g. \"live\")"
    ],
    stream_key: [
      spec: String.t(),
      description: "RTMP stream key or full stream URL path"
    ],
    use_tls: [
      spec: boolean(),
      description: "Use TLS (RTMPS, port 443 by default)",
      default: false
    ]
  )

  # ---------------------------------------------------------------------------
  # Pads
  # ---------------------------------------------------------------------------

  @doc """
  Dynamic input for a single video rendition.

  Accepted format: `%Membrane.H264{alignment: :au}` with AVCC stream structure.

  When multitrack E-RTMP lands each rendition is a separate `:video` pad.
  The sink assigns `TrackId` values starting from 0 in pad-add order.
  """
  def_input_pad :video,
    accepted_format: %H264{alignment: :au},
    availability: :on_request,
    flow_control: :auto

  @doc """
  Dynamic input for audio.

  Accepted formats: `%Membrane.AAC{encapsulation: :none}` or `%Membrane.Opus{}`.

  Typically only one audio pad is connected; the first one receives `TrackId(0)`.
  """
  def_input_pad :audio,
    accepted_format: any_of(%AAC{encapsulation: :none}, %Opus{}),
    availability: :on_request,
    flow_control: :auto

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      client: nil,
      host: opts.host,
      port: opts.port,
      app: opts.app,
      stream_key: opts.stream_key,
      use_tls: opts.use_tls,
      # track_id counters are per media type so video and audio are numbered
      # independently, matching the E-RTMP multitrack spec.
      next_video_track_id: 0,
      next_audio_track_id: 0,
      # %{pad_ref => %{track_id: non_neg_integer(), codec: atom() | nil, config_sent: boolean()}}
      tracks: %{},
      # Set on the first buffer to normalize timestamps to a non-negative origin.
      # RTMP requires uint timestamps; H264 with B-frames can produce negative DTS.
      dts_offset: nil
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    scheme = if state.use_tls, do: "rtmps", else: "rtmp"
    Membrane.Logger.info("Connecting to #{scheme}://#{state.host}:#{state.port}/#{state.app}/#{state.stream_key}")

    case Native.connect(state.host, state.port, state.app, state.stream_key, state.use_tls) do
      {:error, reason} ->
        raise "RTMP connect failed: #{reason}"

      client ->
        Membrane.Logger.info("RTMP connection established")
        {[], %{state | client: client}}
    end
  end

  @impl true
  def handle_pad_added(pad_ref, _ctx, state) do
    {track_id, state} = assign_track_id(pad_ref, state)
    tracks = Map.put(state.tracks, pad_ref, %{track_id: track_id, codec: nil, config_sent: false})
    {[], %{state | tracks: tracks}}
  end

  @impl true
  def handle_stream_format(pad_ref, stream_format, _ctx, state) do
    state = send_codec_config(pad_ref, stream_format, state)
    {[], state}
  end

  @impl true
  def handle_buffer(pad_ref, %Buffer{} = buffer, _ctx, state) do
    %{track_id: track_id, codec: codec, config_sent: config_sent} =
      Map.fetch!(state.tracks, pad_ref)

    state =
      if state.dts_offset == nil do
        dts = buffer.dts || buffer.pts || 0
        %{state | dts_offset: dts}
      else
        state
      end

    if not config_sent do
      Membrane.Logger.warning("Dropping buffer on #{inspect(pad_ref)}: codec config not yet sent")
    else
      send_media(pad_ref, track_id, codec, buffer, state.client, state.dts_offset)
    end

    {[], state}
  end

  @impl true
  def handle_end_of_stream(pad_ref, _ctx, state) do
    Membrane.Logger.debug("End of stream on #{inspect(pad_ref)}")
    {[], state}
  end

  # ---------------------------------------------------------------------------
  # Private – track assignment
  # ---------------------------------------------------------------------------

  defp assign_track_id(Pad.ref(:video, _), state) do
    id = state.next_video_track_id
    {id, %{state | next_video_track_id: id + 1}}
  end

  defp assign_track_id(Pad.ref(:audio, _), state) do
    id = state.next_audio_track_id
    {id, %{state | next_audio_track_id: id + 1}}
  end


  # ---------------------------------------------------------------------------
  # Private – codec config
  # ---------------------------------------------------------------------------

  defp send_codec_config(
         pad_ref,
         %H264{stream_structure: {avcc, dcr}},
         state
       )
       when avcc in [:avc1, :avc3] do
    %{track_id: track_id} = Map.fetch!(state.tracks, pad_ref)
    :ok = Native.send_video_config(state.client, track_id, :h264, dcr)

    state
    |> put_in([:tracks, pad_ref, :codec], :h264)
    |> put_in([:tracks, pad_ref, :config_sent], true)
  end

  defp send_codec_config(
         _pad_ref,
         %H264{stream_structure: stream_structure},
         _state
       ) do
    raise """
    Membrane.ERTMP.Sink received H264 with stream_structure #{inspect(stream_structure)}.
    Only {:avc1, dcr} (AVCC) is supported. Add Membrane.H264.Parser upstream with
    output_stream_structure: :avc1 to convert from Annex B.
    """
  end

  defp send_codec_config(
         pad_ref,
         %AAC{config: {:audio_specific_config, asc}, channels: channels},
         state
       )
       when is_binary(asc) do
    %{track_id: track_id} = Map.fetch!(state.tracks, pad_ref)
    rtmp_channels = map_aac_channels(channels)
    :ok = Native.send_audio_config(state.client, track_id, :aac, asc, rtmp_channels)

    state
    |> put_in([:tracks, pad_ref, :codec], :aac)
    |> put_in([:tracks, pad_ref, :config_sent], true)
  end

  defp send_codec_config(pad_ref, %AAC{}, _state) do
    raise "Membrane.ERTMP.Sink: AAC stream format on #{inspect(pad_ref)} has no audio_specific_config. Add Membrane.AAC.Parser upstream."
  end

  defp send_codec_config(pad_ref, %Opus{channels: channels}, state) do
    %{track_id: track_id} = Map.fetch!(state.tracks, pad_ref)
    # Build a minimal OpusHead (https://wiki.xiph.org/OggOpus#ID_Header)
    # The RTMP crate uses this binary as the AudioConfig data for Opus.
    opus_head = build_opus_head(channels)
    rtmp_channels = if channels <= 1, do: :mono, else: :stereo
    :ok = Native.send_audio_config(state.client, track_id, :opus, opus_head, rtmp_channels)

    state
    |> put_in([:tracks, pad_ref, :codec], :opus)
    |> put_in([:tracks, pad_ref, :config_sent], true)
  end

  # ---------------------------------------------------------------------------
  # Private – media sending
  # ---------------------------------------------------------------------------

  defp send_media(Pad.ref(:video, _), track_id, codec, buffer, client, offset) do
    pts_ns = max((buffer.pts || 0) - offset, 0)
    dts_ns = max((buffer.dts || (buffer.pts || 0)) - offset, 0)
    is_keyframe = h264_keyframe?(buffer)
    :ok = Native.send_video(client, track_id, codec, pts_ns, dts_ns, buffer.payload, is_keyframe)
  end

  defp send_media(Pad.ref(:audio, _), track_id, codec, buffer, client, offset) do
    pts_ns = max((buffer.pts || 0) - offset, 0)
    :ok = Native.send_audio(client, track_id, codec, pts_ns, buffer.payload)
  end

  # ---------------------------------------------------------------------------
  # Private – utilities
  # ---------------------------------------------------------------------------

  defp h264_keyframe?(%Buffer{metadata: %{h264: %{key_frame: true}}}), do: true
  defp h264_keyframe?(_), do: false

  defp map_aac_channels(1), do: :mono
  defp map_aac_channels(:mono), do: :mono
  defp map_aac_channels(_), do: :stereo

  # Opus ID header as defined in RFC 7845 / OggOpus spec.
  # Version 1, channel count, pre-skip 312 (standard), sample rate 48000.
  defp build_opus_head(channels) do
    channel_count = channels || 2
    # magic, version, channels, pre-skip (LE u16), input_sample_rate (LE u32),
    # output_gain (LE i16), channel_mapping_family
    <<
      "OpusHead",
      1::8,
      channel_count::8,
      312::little-16,
      48_000::little-32,
      0::little-16,
      0::8
    >>
  end
end
