# Streams test/fixtures/input.h264 (H.264 Annex B) and test/fixtures/input.aac
# (ADTS-encapsulated AAC) to an RTMP server using Membrane.ERTMP.Sink.
#
# Usage:
#   mix run examples/sink_example.exs [rtmp://host:port/app/key]
#
# The RTMP URL defaults to rtmp://localhost:1935/live/test.
#
# You can run an RTMP server localy using FFmpeg:
# ffmpeg -listen 1 -i rtmp://localhost:1935/live/test -c copy output.flv -y

defmodule ERTMP.Example.Pipeline do
  use Membrane.Pipeline

  require Membrane.Pad, as: Pad

  @input_path "test/fixtures/input_long.mp4"

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      child(:video_source, %Membrane.File.Source{location: @input_path})
      |> child(:demuxer, Membrane.MP4.Demuxer.ISOM)
      |> via_out(:output, options: [kind: :video])
      |> child(:parser_video, %Membrane.H264.Parser{output_stream_structure: :avc1, output_alignment: :au})
      |> child(Membrane.Realtimer)
      |> via_in(Pad.ref(:video, :main))
      |> child(:sink, %Membrane.ERTMP.Sink{
        host: opts.host,
        port: opts.port,
        app: opts.app,
        stream_key: opts.stream_key,
        use_tls: opts.use_tls
      }),
      get_child(:demuxer)
      |> via_out(:output, options: [kind: :audio])
      |> child(:audio_parser, %Membrane.AAC.Parser{
        out_encapsulation: :ADTS
      })
      |> child(:aac_parser, %Membrane.AAC.Parser{
        out_encapsulation: :none,
        output_config: :audio_specific_config
      })
      |> child(Membrane.Realtimer)
      |> via_in(Pad.ref(:audio, :main))
      |> get_child(:sink)
    ]

    {[spec: spec], %{pending_eos: 2}}
  end

  @impl true
  def handle_element_end_of_stream(:sink, _pad, _context, state) do
    state = update_in(state.pending_eos, & &1-1)
    actions = if state.pending_eos == 0, do: [terminate: :normal], else: []
    {actions, state}
  end

  @impl true
  def handle_element_end_of_stream(_child, _pad, _context, state) do
    {[], state}
  end
end

defmodule Helper do
  def parse_rtmp_url(url) do
    uri = URI.parse(url)
    use_tls = uri.scheme == "rtmps"
    [_, app | key_parts] = String.split(uri.path, "/")

    %{
      host: uri.host,
      port: uri.port || if(use_tls, do: 443, else: 1935),
      app: app,
      stream_key: Enum.join(key_parts, "/"),
      use_tls: use_tls
    }
  end
end

rtmp_url = System.argv() |> List.first() || "rtmp://localhost:1935/live/test"
opts = Helper.parse_rtmp_url(rtmp_url)

IO.puts("Connecting to #{rtmp_url} …")
{:ok, _supervisor, pipeline} = Membrane.Pipeline.start_link(ERTMP.Example.Pipeline, opts)
ref = Process.monitor(pipeline)

receive do
  {:DOWN, ^ref, :process, _pid, :normal} ->
    :ok

  {:DOWN, ^ref, :process, _pid, reason} ->
    IO.puts("Pipeline failed: #{inspect(reason)}")
    System.halt(1)
end
