defmodule Membrane.ERTMP.SinkIntegrationTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  require Membrane.Pad, as: Pad
  alias Membrane.ERTMP.Sink
  alias Membrane.Testing

  @h264_fixture "test/fixtures/input.h264"
  @aac_fixture "test/fixtures/input.aac"
  @opus_fixture "test/fixtures/input.ogg"
  @vp8_fixture "test/fixtures/input_vp8.ivf"
  @vp9_fixture "test/fixtures/input_vp9.ivf"

  @moduletag :integration
  @moduletag tmp_dir: true

  setup context do
    unless System.find_executable("ffmpeg") do
      raise "ffmpeg not found"
    end

    port = find_free_port()
    output_path = Path.join(context.tmp_dir, "output.flv")
    ffmpeg_port = start_ffmpeg_server(port, output_path)
    on_exit(fn -> stop_ffmpeg(ffmpeg_port) end)

    Process.sleep(500)

    {:ok, rtmp_port: port, ffmpeg_output: output_path, ffmpeg_port: ffmpeg_port}
  end

  test "sink streams H264+AAC fixture files to ffmpeg via RTMP",
       %{rtmp_port: port, ffmpeg_output: output_path, ffmpeg_port: ffmpeg_port} do
    pipeline = build_pipeline(port, h264_spec(), aac_spec())

    assert_end_of_stream(pipeline, :sink, Pad.ref(:video, :main), 15_000)
    assert_end_of_stream(pipeline, :sink, Pad.ref(:audio, :main), 15_000)

    Testing.Pipeline.terminate(pipeline)
    wait_for_ffmpeg(ffmpeg_port)

    assert File.stat!(output_path).size > 0
  end

  test "sink streams H264+Opus fixture files to ffmpeg via RTMP",
       %{rtmp_port: port, ffmpeg_output: output_path, ffmpeg_port: ffmpeg_port} do
    pipeline = build_pipeline(port, h264_spec(), opus_spec())

    assert_end_of_stream(pipeline, :sink, Pad.ref(:video, :main), 15_000)
    assert_end_of_stream(pipeline, :sink, Pad.ref(:audio, :main), 15_000)

    Testing.Pipeline.terminate(pipeline)
    wait_for_ffmpeg(ffmpeg_port)

    assert File.stat!(output_path).size > 0
  end

  test "sink streams VP8+AAC fixture files to ffmpeg via RTMP",
       %{rtmp_port: port, ffmpeg_output: output_path, ffmpeg_port: ffmpeg_port} do
    pipeline = build_pipeline(port, vp8_spec(), aac_spec())

    assert_end_of_stream(pipeline, :sink, Pad.ref(:video, :main), 15_000)
    assert_end_of_stream(pipeline, :sink, Pad.ref(:audio, :main), 15_000)

    Testing.Pipeline.terminate(pipeline)
    wait_for_ffmpeg(ffmpeg_port)

    assert File.stat!(output_path).size > 0
  end

  test "sink streams VP9+AAC fixture files to ffmpeg via RTMP",
       %{rtmp_port: port, ffmpeg_output: output_path, ffmpeg_port: ffmpeg_port} do
    pipeline = build_pipeline(port, vp9_spec(), aac_spec())

    assert_end_of_stream(pipeline, :sink, Pad.ref(:video, :main), 15_000)
    assert_end_of_stream(pipeline, :sink, Pad.ref(:audio, :main), 15_000)

    Testing.Pipeline.terminate(pipeline)
    wait_for_ffmpeg(ffmpeg_port)

    assert File.stat!(output_path).size > 0
  end

  defp wait_for_ffmpeg(ffmpeg_port) do
    receive do
      {^ffmpeg_port, {:exit_status, _}} -> :ok
      {^ffmpeg_port, {:data, _}} -> wait_for_ffmpeg(ffmpeg_port)
    after
      5_000 -> :ok
    end
  end

  defp find_free_port do
    {:ok, socket} = :gen_tcp.listen(0, reuseaddr: true)
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp start_ffmpeg_server(port, output_path) do
    cmd = "ffmpeg -y -listen 1 -i rtmp://127.0.0.1:#{port}/live/test -c copy #{output_path} 2>&1"
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
    _exception -> :ok
  end

  defp build_pipeline(port, video_spec, audio_spec) do
    sink = %Sink{host: "127.0.0.1", port: port, app: "live", stream_key: "test"}

    Testing.Pipeline.start_link_supervised!(
      spec: [
        video_spec |> via_in(Pad.ref(:video, :main)) |> child(:sink, sink),
        audio_spec |> via_in(Pad.ref(:audio, :main)) |> get_child(:sink)
      ]
    )
  end

  defp h264_spec do
    child(:video_source, %Membrane.File.Source{location: @h264_fixture})
    |> child(:h264_parser, %Membrane.H264.Parser{
      output_stream_structure: :avc1,
      generate_best_effort_timestamps: %{framerate: {25, 1}}
    })
  end

  defp vp8_spec do
    child(:video_source, %Membrane.File.Source{location: @vp8_fixture})
    |> child(:ivf_deserializer, Membrane.IVF.Deserializer)
  end

  defp vp9_spec do
    child(:video_source, %Membrane.File.Source{location: @vp9_fixture})
    |> child(:ivf_deserializer, Membrane.IVF.Deserializer)
  end

  defp aac_spec do
    child(:audio_source, %Membrane.File.Source{location: @aac_fixture})
    |> child(:aac_parser, %Membrane.AAC.Parser{
      out_encapsulation: :none,
      output_config: :audio_specific_config
    })
  end

  defp opus_spec do
    child(:opus_source, %Membrane.File.Source{location: @opus_fixture})
    |> child(:ogg_demuxer, Membrane.Ogg.Demuxer)
    |> child(:opus_parser, %Membrane.Opus.Parser{generate_best_effort_timestamps?: true})
  end
end
