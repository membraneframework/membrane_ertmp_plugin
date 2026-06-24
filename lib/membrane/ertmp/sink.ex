defmodule Membrane.ERTMP.Sink do
  @moduledoc """
  Membrane sink that publishes an audio/video stream to an RTMP(S) server
  using Enhanced RTMP (E-RTMP), backed by the Rust `rtmp` crate from
  software-mansion/smelter.

  ## Pads

  Both :audio and :video pads are **dynamic** (`:on_request`) so that the element can later
  accept multiple video renditions for IVS multitrack once the underlying
  crate gains multitrack support.  For a single-rendition stream connect
  exactly one `:video` pad and one `:audio` pad:

      child(:sink, %Membrane.ERTMP.Sink{host: "rtmp.example.com", ...})
      |> via_in(Pad.ref(:video, :main))
      ...
      |> via_in(Pad.ref(:audio, :main))
      ...
  """

  use Membrane.Sink

  require Membrane.Logger
  require Membrane.Pad, as: Pad

  alias Membrane.{AAC, H264, Opus, VP8, VP9}
  alias Membrane.Buffer
  alias Membrane.ERTMP.Native

  defmodule State do
    @moduledoc false

    @type codec :: :h264 | :vp8 | :vp9 | :aac | :opus

    @type track :: %{
            track_id: non_neg_integer(),
            codec: codec() | nil,
            offset_pts: Membrane.Time.t() | nil,
            offset_dts: Membrane.Time.t() | nil
          }

    @type t :: %__MODULE__{
            client: Native.client() | nil,
            host: String.t(),
            port: 1..65_535,
            app: String.t(),
            stream_key: String.t(),
            use_tls: boolean(),
            next_video_track_id: non_neg_integer(),
            next_audio_track_id: non_neg_integer(),
            tracks: %{Pad.ref() => track()}
          }

    @enforce_keys [:host, :port, :app, :stream_key, :use_tls]
    defstruct @enforce_keys ++
                [
                  client: nil,
                  next_video_track_id: 0,
                  next_audio_track_id: 0,
                  tracks: %{}
                ]
  end

  def_options host: [
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

  def_input_pad :video,
    accepted_format:
      any_of(
        %H264{alignment: :au, stream_structure: {avc, _dcr}} when avc in [:avc1, :avc3],
        %VP8{},
        %VP9{}
      ),
    availability: :on_request,
    flow_control: :auto

  def_input_pad :audio,
    accepted_format: any_of(%AAC{encapsulation: :none}, %Opus{}),
    availability: :on_request,
    flow_control: :auto

  @impl true
  def handle_init(_ctx, opts) do
    state = %State{
      host: opts.host,
      port: opts.port,
      app: opts.app,
      stream_key: opts.stream_key,
      use_tls: opts.use_tls
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    scheme = if state.use_tls, do: "rtmps", else: "rtmp"

    Membrane.Logger.info(
      "Connecting to #{scheme}://#{state.host}:#{state.port}/#{state.app}/#{state.stream_key}"
    )

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

    tracks =
      Map.put(state.tracks, pad_ref, %{
        track_id: track_id,
        codec: nil,
        offset_pts: nil,
        offset_dts: nil
      })

    {[], %{state | tracks: tracks}}
  end

  @impl true
  def handle_stream_format(pad_ref, stream_format, _ctx, state) do
    state = send_codec_config(pad_ref, stream_format, state)
    {[], state}
  end

  @impl true
  def handle_buffer(pad_ref, %Buffer{} = buffer, _ctx, state) do
    %{
      track_id: track_id,
      codec: codec,
      offset_pts: offset_pts,
      offset_dts: offset_dts
    } =
      Map.fetch!(state.tracks, pad_ref)

    offset_pts = offset_pts || buffer.pts || buffer.dts
    offset_dts = offset_dts || buffer.dts || buffer.pts
    state = put_in(state.tracks[pad_ref].offset_pts, offset_pts)
    state = put_in(state.tracks[pad_ref].offset_dts, offset_dts)

    send_media(
      pad_ref,
      track_id,
      codec,
      buffer,
      state.client,
      offset_pts,
      offset_dts
    )

    {[], state}
  end

  @spec assign_track_id(Pad.ref(), State.t()) :: {non_neg_integer(), State.t()}
  defp assign_track_id(Pad.ref(:video, _id), state) do
    id = state.next_video_track_id
    {id, %{state | next_video_track_id: id + 1}}
  end

  defp assign_track_id(Pad.ref(:audio, _id), state) do
    id = state.next_audio_track_id
    {id, %{state | next_audio_track_id: id + 1}}
  end

  @spec send_codec_config(Pad.ref(), Membrane.StreamFormat.t(), State.t()) :: State.t()
  defp send_codec_config(pad_ref, stream_format, state) do
    %{track_id: track_id} = Map.fetch!(state.tracks, pad_ref)

    codec_name = do_send_codec_config(track_id, stream_format, state)

    %{state | tracks: put_in(state.tracks, [pad_ref, :codec], codec_name)}
  end

  @spec do_send_codec_config(non_neg_integer(), Membrane.StreamFormat.t(), State.t()) ::
          State.codec()
  defp do_send_codec_config(
         track_id,
         %H264{stream_structure: {avcc, dcr}},
         state
       )
       when avcc in [:avc1, :avc3] do
    :ok = Native.send_video_config(state.client, track_id, :h264, dcr)
    :h264
  end

  defp do_send_codec_config(track_id, %VP8{}, state) do
    :ok = Native.send_video_config(state.client, track_id, :vp8, <<>>)
    :vp8
  end

  defp do_send_codec_config(track_id, %VP9{}, state) do
    :ok = Native.send_video_config(state.client, track_id, :vp9, <<>>)
    :vp9
  end

  defp do_send_codec_config(
         track_id,
         %AAC{config: {:audio_specific_config, asc}, channels: channels},
         state
       )
       when is_binary(asc) do
    rtmp_channels = map_channels(channels)
    :ok = Native.send_audio_config(state.client, track_id, :aac, asc, rtmp_channels)
    :aac
  end

  defp do_send_codec_config(track_id, %Opus{channels: channels}, state) do
    opus_head = build_opus_head(channels)
    rtmp_channels = map_channels(channels)
    :ok = Native.send_audio_config(state.client, track_id, :opus, opus_head, rtmp_channels)
    :opus
  end

  @spec send_media(
          Pad.ref(),
          non_neg_integer(),
          State.codec(),
          Buffer.t(),
          Native.client(),
          Membrane.Time.t(),
          Membrane.Time.t()
        ) :: :ok
  defp send_media(Pad.ref(:video, _id), track_id, codec, buffer, client, offset_pts, offset_dts) do
    pts_ns = Membrane.Time.as_nanoseconds((buffer.pts || buffer.dts) - offset_pts, :round)
    dts_ns = Membrane.Time.as_nanoseconds((buffer.dts || buffer.pts) - offset_dts, :round)
    is_keyframe = video_keyframe?(codec, buffer)
    :ok = Native.send_video(client, track_id, codec, pts_ns, dts_ns, buffer.payload, is_keyframe)
  end

  defp send_media(Pad.ref(:audio, _id), track_id, codec, buffer, client, offset_pts, _offset_dts) do
    pts_ns = Membrane.Time.as_nanoseconds((buffer.pts || buffer.dts) - offset_pts, :round)
    :ok = Native.send_audio(client, track_id, codec, pts_ns, buffer.payload)
  end

  @spec video_keyframe?(State.codec(), Buffer.t()) :: boolean()
  defp video_keyframe?(:h264, %Buffer{metadata: %{h264: %{key_frame?: true}}}), do: true
  defp video_keyframe?(:vp8, %Buffer{metadata: %{vp8: %{is_keyframe: true}}}), do: true
  defp video_keyframe?(:vp9, %Buffer{metadata: %{vp9: %{is_keyframe: true}}}), do: true
  defp video_keyframe?(_codec, _buffer), do: false

  # OpusHead plays a similar role to the audio specific config for AAC
  @spec build_opus_head(non_neg_integer()) :: binary()
  defp build_opus_head(channels) do
    <<
      # Magic signature
      "OpusHead",
      # Version (always 1)
      1::8,
      # Channel count
      channels::8,
      # Pre-skip delay
      312::16-little,
      # Original sample rate (before encoding) - we can safely set it to Opus native 48kHz as we don't have that information available
      48_000::32-little,
      # Output gain (0 = no gain)
      0::16-little,
      # Mapping family (0 = mono/stereo)
      0::8
    >>
  end

  @spec map_channels(non_neg_integer()) :: :mono | :stereo
  defp map_channels(1), do: :mono
  defp map_channels(2), do: :stereo
  defp map_channels(channels) do
    raise "Unsupported number of channels: #{channels}. Only 1 (:mono) or 2 (:stereo) channels are supported."
  end
end
