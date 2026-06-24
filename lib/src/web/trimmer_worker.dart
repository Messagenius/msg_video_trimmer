// The Web Worker source that performs the actual trim off the main thread.
//
// It is shipped as a string, turned into a Blob URL at runtime, and spawned as
// a module worker (so it can `import` mp4box.js from a CDN). The worker:
//   1. demuxes the input MP4 with mp4box.js,
//   2. decodes the in-range video (and optionally audio) samples with WebCodecs,
//   3. re-encodes them, rebasing timestamps to zero,
//   4. muxes the result back into an MP4 with mp4box.js,
//   5. posts progress messages and finally the output bytes.
//
// Keeping this in JS (rather than Dart-compiled-to-JS) avoids pulling the heavy,
// browser-specific codec glue through the Dart isolate and lets us use the
// mp4box ESM build directly.
const String trimmerWorkerSource = r'''
import MP4Box from "https://cdn.jsdelivr.net/npm/mp4box@0.5.2/+esm";

let sourceBuffer = null;

self.onmessage = async (e) => {
  const msg = e.data;
  try {
    if (msg.cmd === "load") {
      const resp = await fetch(msg.url);
      const buf = await resp.arrayBuffer();
      sourceBuffer = buf;
      self.postMessage({ type: "loaded" });
    } else if (msg.cmd === "trim") {
      if (!sourceBuffer) throw new Error("No video loaded");
      const out = await trim(sourceBuffer, msg.startMs, msg.endMs, msg.includeAudio);
      self.postMessage({ type: "done", buffer: out }, [out]);
    }
  } catch (err) {
    self.postMessage({ type: "error", message: String(err && err.message || err) });
  }
};

function readFile(buffer) {
  return new Promise((resolve, reject) => {
    const file = MP4Box.createFile();
    file.onError = (err) => reject(new Error(err));
    file.onReady = (info) => resolve({ file, info });
    const ab = buffer.slice(0);
    ab.fileStart = 0;
    file.appendBuffer(ab);
    file.flush();
  });
}

async function trim(buffer, startMs, endMs, includeAudio) {
  const { file, info } = await readFile(buffer);
  const videoTrack = info.videoTracks && info.videoTracks[0];
  if (!videoTrack) throw new Error("No video track");
  const audioTrack = includeAudio && info.audioTracks && info.audioTracks[0];

  const startUs = startMs * 1000;
  const endUs = endMs * 1000;

  const out = MP4Box.createFile();

  // Collect samples per track via mp4box extraction.
  const samples = {};
  await new Promise((resolve) => {
    file.onSamples = (id, user, sampleList) => {
      samples[id] = (samples[id] || []).concat(sampleList);
    };
    file.setExtractionOptions(videoTrack.id, null, { nbSamples: Infinity });
    if (audioTrack) file.setExtractionOptions(audioTrack.id, null, { nbSamples: Infinity });
    file.onFlush = () => resolve();
    file.start();
    file.flush();
    // mp4box delivers onSamples synchronously during flush in practice; resolve
    // on the next microtask if onFlush did not fire.
    Promise.resolve().then(resolve);
  });

  const outVideoId = await transcodeVideo(
    out, videoTrack, samples[videoTrack.id] || [], startUs, endUs);
  if (audioTrack) {
    await transcodeAudio(
      out, audioTrack, samples[audioTrack.id] || [], startUs, endUs);
  }

  out.flush();
  const ab = out.getBuffer();
  return ab instanceof ArrayBuffer ? ab : ab.buffer;
}

function inRange(sampleCtsUs, startUs, endUs) {
  return sampleCtsUs >= startUs && sampleCtsUs <= endUs;
}

async function transcodeVideo(out, track, sampleList, startUs, endUs) {
  const timescale = track.timescale;
  const toUs = (t) => (t / timescale) * 1e6;

  let trackId = null;
  let configured = false;
  const encoder = new VideoEncoder({
    output: (chunk, meta) => {
      if (!configured && meta && meta.decoderConfig) {
        trackId = out.addTrack({
          timescale: 1e6,
          width: track.video.width,
          height: track.video.height,
          avcDecoderConfigRecord: meta.decoderConfig.description,
        });
        configured = true;
      }
      const data = new Uint8Array(chunk.byteLength);
      chunk.copyTo(data);
      out.addSample(trackId, data, {
        duration: chunk.duration || 0,
        cts: chunk.timestamp,
        dts: chunk.timestamp,
        is_sync: chunk.type === "key",
      });
    },
    error: (e) => { throw e; },
  });
  encoder.configure({
    codec: "avc1.42001f",
    width: track.video.width,
    height: track.video.height,
    bitrate: 4_000_000,
  });

  const decoder = new VideoDecoder({
    output: (frame) => {
      const ts = frame.timestamp;
      if (inRange(ts, startUs, endUs)) {
        const rebased = new VideoFrame(frame, { timestamp: ts - startUs });
        encoder.encode(rebased, { keyFrame: false });
        rebased.close();
      }
      frame.close();
    },
    error: (e) => { throw e; },
  });
  decoder.configure({
    codec: track.codec,
    description: avcConfig(track),
  });

  const total = sampleList.length;
  for (let i = 0; i < total; i++) {
    const s = sampleList[i];
    const ctsUs = toUs(s.cts);
    // Decode from the preceding keyframe so in-range frames are reconstructable.
    if (ctsUs > endUs) break;
    decoder.decode(new EncodedVideoChunk({
      type: s.is_sync ? "key" : "delta",
      timestamp: ctsUs,
      duration: toUs(s.duration),
      data: s.data,
    }));
    if (i % 10 === 0) {
      self.postMessage({ type: "progress", value: (i / total) * 100 });
    }
  }
  await decoder.flush();
  await encoder.flush();
  decoder.close();
  encoder.close();
  self.postMessage({ type: "progress", value: 100 });
  return trackId;
}

async function transcodeAudio(out, track, sampleList, startUs, endUs) {
  const timescale = track.timescale;
  const toUs = (t) => (t / timescale) * 1e6;
  let trackId = null;
  let configured = false;

  const encoder = new AudioEncoder({
    output: (chunk, meta) => {
      if (!configured) {
        trackId = out.addTrack({
          timescale: 1e6,
          channel_count: track.audio.channel_count,
          samplerate: track.audio.sample_rate,
          hdlr: "soun",
          type: "mp4a",
        });
        configured = true;
      }
      const data = new Uint8Array(chunk.byteLength);
      chunk.copyTo(data);
      out.addSample(trackId, data, {
        duration: chunk.duration || 0,
        cts: chunk.timestamp,
        dts: chunk.timestamp,
        is_sync: true,
      });
    },
    error: (e) => { throw e; },
  });
  encoder.configure({
    codec: "mp4a.40.2",
    sampleRate: track.audio.sample_rate,
    numberOfChannels: track.audio.channel_count,
    bitrate: 128_000,
  });

  const decoder = new AudioDecoder({
    output: (frame) => {
      if (inRange(frame.timestamp, startUs, endUs)) {
        encoder.encode(frame);
      }
      frame.close();
    },
    error: (e) => { throw e; },
  });
  decoder.configure({ codec: track.codec, sampleRate: track.audio.sample_rate, numberOfChannels: track.audio.channel_count });

  for (const s of sampleList) {
    const ctsUs = toUs(s.cts);
    if (ctsUs > endUs) break;
    decoder.decode(new EncodedAudioChunk({
      type: "key",
      timestamp: ctsUs,
      duration: toUs(s.duration),
      data: s.data,
    }));
  }
  await decoder.flush();
  await encoder.flush();
  decoder.close();
  encoder.close();
}

// Reconstructs the avcC/decoder description box that WebCodecs needs.
function avcConfig(track) {
  const trak = track.trak || null;
  if (trak && trak.mdia && trak.mdia.minf && trak.mdia.minf.stbl) {
    const entries = trak.mdia.minf.stbl.stsd.entries;
    for (const e of entries) {
      const box = e.avcC || e.hvcC || e.vpcC;
      if (box) {
        const stream = new MP4Box.DataStream(undefined, 0, MP4Box.DataStream.BIG_ENDIAN);
        box.write(stream);
        return new Uint8Array(stream.buffer, 8); // strip box header
      }
    }
  }
  return undefined;
}
''';
