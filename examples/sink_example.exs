# Streams test/fixtures/input.h264 (H.264 Annex B) and test/fixtures/input.opus
# (Ogg/Opus) to an RTMP server using Membrane.ERTMP.Sink.
#
# Usage:
#   mix run examples/sink_example.exs [rtmp://host:port/app/key]
#
# The RTMP URL defaults to rtmp://localhost:1935/live/test.
#
# Prepare fixture files with ffmpeg (run once):
#   ffmpeg -i your_source.mp4 -an -vcodec copy -f h264 test/fixtures/input.h264
#   ffmpeg -i your_source.mp4 -vn -c:a libopus -f ogg test/fixtures/input.opus

defmodule ERTMP.Example.Pipeline do
  use Membrane.Pipeline

  require Membrane.Pad, as: Pad

  @video_path "test/fixtures/input.h264"
  @audio_path "test/fixtures/input.opus"

  @impl true
  def handle_init(_ctx, %{host: host, port: port, app: app, stream_key: stream_key}) do
    spec = [
      child(:video_source, %Membrane.File.Source{location: @video_path})
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_stream_structure: :avc1,
        generate_best_effort_timestamps: %{framerate: {25, 1}}
      })
      |> child(Membrane.Realtimer)
      |> child(%Membrane.Debug.Filter{handle_buffer: &IO.inspect(&1.pts, label: :video)})
      |> via_in(Pad.ref(:video, :main))
      |> child(:sink, %Membrane.ERTMP.Sink{
        host: host,
        port: port,
        app: app,
        stream_key: stream_key,
        use_tls: true
      }),
      child(:audio_source, %Membrane.File.Source{location: @audio_path})
      |> child(:ogg_demuxer, Membrane.Ogg.Demuxer)
      |> child(:opus_parser, %Membrane.Opus.Parser{generate_best_effort_timestamps?: true})
      |> child(Membrane.Realtimer)
      |> child(%Membrane.Debug.Filter{handle_buffer: &IO.inspect(&1.pts, label: :audio)})
      |> via_in(Pad.ref(:audio, :main))
      |> get_child(:sink)
    ]

    {[spec: spec], %{pending_eos: 2}}
  end

  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, %{pending_eos: 1} = state) do
    IO.puts("Stream finished.")
    {[terminate: :normal], %{state | pending_eos: 0}}
  end

  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    {[], %{state | pending_eos: state.pending_eos - 1}}
  end

  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end
end

defmodule Helper do
  def parse_rtmp_url(url) do
    case Regex.named_captures(
           ~r{rtmps?://(?<host>[^:/]+)(?::(?<port>\d+))?/(?<app>[^/]+)/(?<key>.+)},
           url
         ) do
      %{"host" => host, "port" => port_str, "app" => app, "key" => key} ->
        %{
          host: host,
          port: if(port_str == "", do: 1935, else: String.to_integer(port_str)),
          app: app,
          stream_key: key
        }

      nil ->
        IO.puts("Invalid RTMP URL: #{url}")
        System.halt(1)
    end
  end
end

rtmp_url = System.argv() |> List.first() || "rtmp://localhost:1935/live/test"
opts = Helper.parse_rtmp_url(rtmp_url)

IO.puts("Connecting to #{rtmp_url} …")
{:ok, supervisor, pipeline} = Membrane.Pipeline.start_link(ERTMP.Example.Pipeline, opts)
ref = Process.monitor(pipeline)

receive do
  {:DOWN, ^ref, :process, _pid, :normal} ->
    :ok

  {:DOWN, ^ref, :process, _pid, reason} ->
    IO.puts("Pipeline failed: #{inspect(reason)}")
    Supervisor.stop(supervisor)
    System.halt(1)
end

Supervisor.stop(supervisor)
