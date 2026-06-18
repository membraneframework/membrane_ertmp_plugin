defmodule Membrane.ERTMP.Native do
  @moduledoc false

  use Rustler, otp_app: :membrane_ertmp_plugin, crate: :membrane_ertmp

  @type client() :: reference()

  @spec connect(String.t(), 1..65_535, String.t(), String.t(), boolean()) ::
          client() | {:error, String.t()}
  def connect(_host, _port, _app, _stream_key, _use_tls),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec send_video_config(client(), non_neg_integer(), atom(), binary()) ::
          :ok | {:error, String.t()}
  def send_video_config(_client, _track_id, _codec, _data),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec send_video(
          client(),
          non_neg_integer(),
          atom(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          boolean()
        ) :: :ok | {:error, String.t()}
  def send_video(_client, _track_id, _codec, _pts_ns, _dts_ns, _data, _is_keyframe),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec send_audio_config(client(), non_neg_integer(), atom(), binary(), atom()) ::
          :ok | {:error, String.t()}
  def send_audio_config(_client, _track_id, _codec, _data, _channels),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec send_audio(client(), non_neg_integer(), atom(), non_neg_integer(), binary()) ::
          :ok | {:error, String.t()}
  def send_audio(_client, _track_id, _codec, _pts_ns, _data),
    do: :erlang.nif_error(:nif_not_loaded)
end
