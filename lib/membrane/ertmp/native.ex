defmodule Membrane.ERTMP.Native do
  @moduledoc false

  use Rustler, otp_app: :membrane_ertmp_plugin, crate: :membrane_ertmp

  def connect(_host, _port, _app, _stream_key, _use_tls),
    do: :erlang.nif_error(:nif_not_loaded)

  def send_video_config(_client, _track_id, _codec, _data),
    do: :erlang.nif_error(:nif_not_loaded)

  def send_video(_client, _track_id, _codec, _pts_ns, _dts_ns, _data, _is_keyframe),
    do: :erlang.nif_error(:nif_not_loaded)

  def send_audio_config(_client, _track_id, _codec, _data, _channels),
    do: :erlang.nif_error(:nif_not_loaded)

  def send_audio(_client, _track_id, _codec, _pts_ns, _data),
    do: :erlang.nif_error(:nif_not_loaded)
end
