use bytes::Bytes;
use rtmp::{
    AudioChannels, AudioConfig, AudioData, RtmpAudioCodec, RtmpClient, RtmpClientConfig,
    RtmpVideoCodec, TrackId, VideoConfig, VideoData,
};
use rustler::{Atom, Binary, Env, Error, NifResult, ResourceArc, Term};
use std::sync::Mutex;
use std::time::Duration;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        h264,
        vp8,
        vp9,
        aac,
        opus,
        mono,
        stereo,
    }
}

pub struct ClientResource(Mutex<Option<RtmpClient>>);

#[allow(non_local_definitions)]
fn on_load(env: Env, _: Term) -> bool {
    rustler::resource!(ClientResource, env)
}

rustler::init!("Elixir.Membrane.ERTMP.Native", load = on_load);

#[rustler::nif(schedule = "DirtyIo")]
fn connect(
    host: String,
    port: u16,
    app: String,
    stream_key: String,
    use_tls: bool,
) -> NifResult<ResourceArc<ClientResource>> {
    let config = RtmpClientConfig::new(host, app, stream_key)
        .with_port(port)
        .with_tls(use_tls);
    RtmpClient::connect(config)
        .map(|client| ResourceArc::new(ClientResource(Mutex::new(Some(client)))))
        .map_err(|e| Error::Term(Box::new(e.to_string())))
}

#[rustler::nif(schedule = "DirtyIo")]
fn send_video_config(
    resource: ResourceArc<ClientResource>,
    track_id: u8,
    codec: Atom,
    data: Binary,
) -> NifResult<Atom> {
    let codec = parse_video_codec(codec)?;
    let event = VideoConfig {
        track_id: TrackId(track_id),
        codec,
        data: Bytes::copy_from_slice(data.as_slice()),
    };
    with_client(&resource, |c| c.send(event))
}

#[rustler::nif(schedule = "DirtyIo")]
fn send_video(
    resource: ResourceArc<ClientResource>,
    track_id: u8,
    codec: Atom,
    pts_ns: u64,
    dts_ns: u64,
    data: Binary,
    is_keyframe: bool,
) -> NifResult<Atom> {
    let codec = parse_video_codec(codec)?;
    let event = VideoData {
        track_id: TrackId(track_id),
        codec,
        pts: Duration::from_nanos(pts_ns),
        dts: Duration::from_nanos(dts_ns),
        data: Bytes::copy_from_slice(data.as_slice()),
        is_keyframe,
    };
    with_client(&resource, |c| c.send(event))
}

#[rustler::nif(schedule = "DirtyIo")]
fn send_audio_config(
    resource: ResourceArc<ClientResource>,
    track_id: u8,
    codec: Atom,
    data: Binary,
    channels: Atom,
) -> NifResult<Atom> {
    let codec = parse_audio_codec(codec)?;
    let channels = parse_audio_channels(channels)?;
    let event = AudioConfig {
        track_id: TrackId(track_id),
        codec,
        data: Bytes::copy_from_slice(data.as_slice()),
        channels,
    };
    with_client(&resource, |c| c.send(event))
}

#[rustler::nif(schedule = "DirtyIo")]
fn send_audio(
    resource: ResourceArc<ClientResource>,
    track_id: u8,
    codec: Atom,
    pts_ns: u64,
    data: Binary,
) -> NifResult<Atom> {
    let codec = parse_audio_codec(codec)?;
    let event = AudioData {
        track_id: TrackId(track_id),
        codec,
        pts: Duration::from_nanos(pts_ns),
        data: Bytes::copy_from_slice(data.as_slice()),
    };
    with_client(&resource, |c| c.send(event))
}

fn with_client<F>(resource: &ResourceArc<ClientResource>, f: F) -> NifResult<Atom>
where
    F: FnOnce(&mut RtmpClient) -> Result<(), rtmp::RtmpStreamError>,
{
    let mut guard = resource.0.lock().map_err(|_| Error::BadArg)?;
    let client = guard.as_mut().ok_or(Error::BadArg)?;
    f(client).map_err(|e| Error::Term(Box::new(e.to_string())))?;
    Ok(atoms::ok())
}

fn parse_video_codec(atom: Atom) -> NifResult<RtmpVideoCodec> {
    if atom == atoms::h264() {
        Ok(RtmpVideoCodec::H264)
    } else if atom == atoms::vp8() {
        Ok(RtmpVideoCodec::Vp8)
    } else if atom == atoms::vp9() {
        Ok(RtmpVideoCodec::Vp9)
    } else {
        Err(Error::BadArg)
    }
}

fn parse_audio_codec(atom: Atom) -> NifResult<RtmpAudioCodec> {
    if atom == atoms::aac() {
        Ok(RtmpAudioCodec::Aac)
    } else if atom == atoms::opus() {
        Ok(RtmpAudioCodec::Opus)
    } else {
        Err(Error::BadArg)
    }
}

fn parse_audio_channels(atom: Atom) -> NifResult<AudioChannels> {
    if atom == atoms::mono() {
        Ok(AudioChannels::Mono)
    } else if atom == atoms::stereo() {
        Ok(AudioChannels::Stereo)
    } else {
        Err(Error::BadArg)
    }
}
