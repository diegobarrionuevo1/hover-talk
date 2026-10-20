# Voice server

HoverTalk reads with the macOS system voices by default. If you run a speech server on another
machine, HoverTalk can read with its voices instead, and it goes back to the system voice by
itself whenever that machine is off or does not answer.

The tested server is [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI). The voice server
is off until you turn it on, and HoverTalk sends it only the text being read (see
[Privacy](#privacy)).

## 1. Run Kokoro-FastAPI on the other machine

Pick one:

| Machine | Command |
|---|---|
| Any machine with Docker (CPU) | `docker run -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu:latest` |
| NVIDIA GPU with Docker | `docker run --gpus all -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-gpu:latest` |
| Apple Silicon Mac | Clone the repository and run `./start-gpu_mac.sh` (runs natively, not in Docker) |

- The Kokoro-FastAPI README recommends pinning a release tag instead of `latest`, so an update
  does not change the server under you. Replace `latest` with a tag from the project's releases.
- The server listens on port 8880 by default.
- Check it on that machine: `curl http://localhost:8880/v1/audio/voices` lists the voices.

## 2. Let the Mac reach port 8880

Allow incoming TCP connections on port 8880 from your local network in the machine's firewall:

- **Windows:** Windows Defender Firewall > Advanced settings > Inbound Rules > New Rule > Port >
  TCP 8880 > Allow, for the Private profile only.
- **Linux with ufw:** `sudo ufw allow from 192.168.1.0/24 to any port 8880 proto tcp` (use your
  network's range).
- **macOS:** System Settings > Network > Firewall > Options, and allow incoming connections for
  the app that runs the server.

Do not forward the port on your router: anyone who can reach the port can use the server.

## 3. Find the machine's address

- **Windows:** `ipconfig`, the "IPv4 Address" line.
- **Linux:** `hostname -I` or `ip -4 addr`.
- **macOS:** `ipconfig getifaddr en0` (Wi-Fi is usually `en0`).

The address looks like `192.168.1.50`. A DHCP reservation in your router keeps it from changing.

## 4. Set up HoverTalk

1. Open **Settings…** (⌘,) and go to **Voice Server**.
2. Turn on **Use my voice server when it is available**.
3. Enter `http://<address>:8880`, for example `http://192.168.1.50:8880`, and press Return.
   A trailing `/v1` is fine too.
4. Press **Test Connection**. It shows one of:
   - **Available · 120 ms**: the server answered with its voice list.
   - **Unreachable**: no answer. Check that the server runs, the firewall rule, and the address.
   - **Server error (HTTP …)** or **Not a voice server**: something answered, but not a voice
     server at that address.
   - **Blocked: use https for this address**: macOS refused plain http to this name (see
     [Privacy](#privacy)).
   - **Invalid URL**: the field does not hold an `http://` or `https://` address.
5. The first time, macOS asks whether HoverTalk may connect to devices on your local network.
   Allow it.
   If you declined, turn HoverTalk on in System Settings > Privacy & Security > Local Network.
6. Choose a **Server voice**:
   - **Automatic** picks a voice for the language of each text, for example `af_heart` for
     American English and `ef_dora` for Spanish when the server lists them. A text in a language
     the server has no voice for is read with the system voice.
   - Or pick one voice for everything. For voices in other languages, check the list at
     `http://<address>:8880/v1/audio/voices`.

The Voice menu shows the server's status on its first line. HoverTalk always asks the server for
normal speed and changes the speed on the Mac, so speed changes apply in the middle of a sentence.

## What happens when the machine is off

- **At the start of a reading** HoverTalk uses the server only if its last check succeeded. If the
  server was not checked yet (for example right after launch), the reading waits at most 0.8
  seconds for the check, then starts with the system voice if there is no answer.
- **During a reading**, if the server fails (no first byte within 2.5 seconds, no complete answer
  within the sentence's time limit of at most 20 seconds, an error, or audio it cannot play), that
  sentence starts again at once with the system voice, and the rest of the reading uses the system
  voice too. The controller shows a small warning icon ("Voice server unreachable — using system
  voice") and the Voice menu says "Voice server: unreachable — using system voice".
- **Re-checks** follow each failed check after 5, 15 and 30 seconds, then every 60 seconds, and
  run right away when the Mac wakes from sleep or its network changes. A check is one request for
  the voice list; no text is sent.
- **When the server is back**, the next reading uses it again. The reading in progress stays on the
  system voice.

## Privacy

- Off by default. When on, HoverTalk sends the text being read to the address you entered, plus
  requests for the voice list. Nothing else: no cookies, no stored credentials, no cache.
- **Plain http is not encrypted.** Anyone on the same network can read the text in transit. Use
  `http://` only on a network you trust, such as your home network.
- **Anywhere else, use https**, for example a reverse proxy with a TLS certificate, or Tailscale
  with HTTPS certificates enabled (see Tailscale's documentation).
- **What macOS allows over plain http** (App Transport Security): HoverTalk's `Info.plist` sets
  `NSAllowsLocalNetworking`, which allows plain http to names without a dot (`http://studio:8880`),
  to `.local` names (`http://studio.local:8880`) and to IP addresses (`http://192.168.1.50:8880`).
  Plain http to any other name, including a Tailscale name such as
  `http://studio.tailnet.ts.net:8880`, is blocked; use `https://` for those.

## Other servers

Any server can work if it offers the same two endpoints:

- `GET /v1/audio/voices` returning `{"voices": [...]}`, with voice names or objects with an `id`.
  HoverTalk uses it to check the server and to list voices, so a server without it never counts
  as available.
- `POST /v1/audio/speech` taking OpenAI-style JSON and returning a WAV file (16-bit integer or
  32-bit float samples, mono or stereo). HoverTalk sends
  `{"model": "kokoro", "input": "<text>", "voice": "<voice>", "speed": 1, "response_format": "wav"}`.
