defmodule Membrane.ERTMP.SinkIntegrationTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  require Membrane.Pad, as: Pad
  alias Membrane.{Buffer, H264, Opus, Testing}
  alias Membrane.ERTMP.Sink

  @moduletag :integration

  # AVCDecoderConfigurationRecord for 320×240 H.264 Baseline Level 3.0.
  # Layout (ISO 14496-15):
  #   configurationVersion(1) | AVCProfileIndication(1) | profile_compatibility(1) |
  #   AVCLevelIndication(1) | 0xFF (6 reserved + lengthSizeMinusOne=3 → 4-byte NAL lengths) |
  #   0xE1 (3 reserved + numSPS=1) | SPS_length(2) | SPS_NALU(20) |
  #   numPPS=1(1) | PPS_length(2) | PPS_NALU(4)
  @h264_dcr <<
    1,
    66,
    0xC0,
    30,
    0xFF,
    0xE1,
    0,
    20,
    0x67,
    0x42,
    0xC0,
    0x1E,
    0xD9,
    0x00,
    0xA0,
    0x47,
    0xFE,
    0xC8,
    0x08,
    0x80,
    0x00,
    0x00,
    0x1F,
    0x40,
    0x00,
    0x07,
    0xA1,
    0x20,
    1,
    0,
    4,
    0x68,
    0xCE,
    0x38,
    0x80
  >>

  # Minimal AVCC-framed IDR NAL unit: 4-byte length prefix (=1) + nal_unit_type=5 header byte.
  @h264_idr_frame <<0, 0, 0, 1, 0x65>>

  # Two-channel silent Opus SILK frame.
  @opus_silent_frame <<0xF8, 0xFF, 0xFE>>

  setup do
    unless System.find_executable("ffmpeg") do
      raise "ffmpeg not found"
    end

    port = find_free_port()
    ffmpeg_port = start_ffmpeg_server(port)
    on_exit(fn -> stop_ffmpeg(ffmpeg_port) end)

    # Give ffmpeg time to bind and enter listen mode.
    Process.sleep(500)

    {:ok, rtmp_port: port}
  end

  test "sink establishes RTMP connection and delivers audio/video to ffmpeg", %{rtmp_port: port} do
    pipeline = build_pipeline(port)

    assert_end_of_stream(pipeline, :sink, Pad.ref(:video, :main), 10_000)
    assert_end_of_stream(pipeline, :sink, Pad.ref(:audio, :main), 10_000)

    Testing.Pipeline.terminate(pipeline)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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

  defp build_pipeline(port) do
    h264_fmt = %H264{
      width: 320,
      height: 240,
      alignment: :au,
      stream_structure: {:avc1, @h264_dcr}
    }

    opus_fmt = %Opus{channels: 2}

    video_source = %Testing.Source{
      output: [
        %Buffer{
          payload: @h264_idr_frame,
          pts: 0,
          dts: 0,
          metadata: %{h264: %{key_frame: true}}
        }
      ],
      stream_format: h264_fmt
    }

    audio_source = %Testing.Source{
      output: [%Buffer{payload: @opus_silent_frame, pts: 0}],
      stream_format: opus_fmt
    }

    sink = %Sink{host: "127.0.0.1", port: port, app: "live", stream_key: "test"}

    Testing.Pipeline.start_link_supervised!(
      spec: [
        child(:video_source, video_source)
        |> via_in(Pad.ref(:video, :main))
        |> child(:sink, sink),
        child(:audio_source, audio_source)
        |> via_in(Pad.ref(:audio, :main))
        |> get_child(:sink)
      ]
    )
  end
end
