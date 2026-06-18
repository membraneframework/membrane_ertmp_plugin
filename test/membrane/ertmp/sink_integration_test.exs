defmodule Membrane.ERTMP.SinkIntegrationTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  require Membrane.Pad, as: Pad
  alias Membrane.Testing
  alias Membrane.ERTMP.Sink

  @video_fixture "test/fixtures/input.h264"
  @audio_fixture "test/fixtures/input.aac"

  @moduletag :integration

  setup do
    unless System.find_executable("ffmpeg") do
      raise "ffmpeg not found"
    end

    port = find_free_port()
    ffmpeg_port = start_ffmpeg_server(port)
    on_exit(fn -> stop_ffmpeg(ffmpeg_port) end)

    Process.sleep(500)

    {:ok, rtmp_port: port}
  end

  test "sink streams H264+AAC fixture files to ffmpeg via RTMP", %{rtmp_port: port} do
    pipeline = build_file_pipeline(port)

    assert_end_of_stream(pipeline, :sink, Pad.ref(:video, :main), 30_000)
    assert_end_of_stream(pipeline, :sink, Pad.ref(:audio, :main), 30_000)

    Testing.Pipeline.terminate(pipeline)
  end

  defp find_free_port do
    {:ok, socket} = :gen_tcp.listen(0, reuseaddr: true)
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp start_ffmpeg_server(port) do
    cmd = "ffmpeg -y -listen 1 -i rtmp://127.0.0.1:#{port}/live/test -f null - 2>&1"
    Port.open({:spawn, cmd}, [:binary, :exit_status])
  end

  defp stop_ffmpeg(port_ref) do
    with {:os_pid, os_pid} <- :erlang.port_info(port_ref, :os_pid) do
      System.cmd("kill", [to_string(os_pid)])
    end

    if :erlang.port_info(port_ref) != :undefined do
      Port.close(port_ref)
    end
  rescue
    _ -> :ok
  end

  defp build_file_pipeline(port) do
    sink = %Sink{host: "127.0.0.1", port: port, app: "live", stream_key: "test"}

    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:video_source, %Membrane.File.Source{location: @video_fixture})
        |> child(:h264_parser, %Membrane.H264.Parser{
          output_stream_structure: :avc1,
          generate_best_effort_timestamps: %{framerate: {25, 1}}
        })
        |> via_in(Pad.ref(:video, :main))
        |> child(:sink, sink),
        child(:audio_source, %Membrane.File.Source{location: @audio_fixture})
        |> child(:aac_parser, %Membrane.AAC.Parser{
          out_encapsulation: :none,
          output_config: :audio_specific_config
        })
        |> via_in(Pad.ref(:audio, :main))
        |> get_child(:sink)
      ]
    )
  end
end
