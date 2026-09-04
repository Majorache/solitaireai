# Solitaire AI — iPhone app (Windows only, free Apple ID, no Mac needed)

Two parts inside one app:

- **Solitaire AI** — the home-screen icon: server, bot on/off, dry run, speed,
  live status and recent activity.
- **Solitaire AI Capture** — a screen-recorder add-on. iOS gives it live frames
  after you approve the recording once. It sends frames to the dashboard AI and
  publishes the chosen move back to it.

The app and the recorder do **not** share private storage — everything goes
through your dashboard, so **no paid Apple Developer account and no app group
are needed**. Your normal free Apple ID is enough. Tapping is done by the
separate jailbreak helper, which reads the move from the dashboard.

Free Apple ID limits: the app stops working after **7 days** and must be
re-installed with Sideloadly (one click, keeps your settings, which live on the
dashboard).

## 1. Build the app (no Mac)

1. Create a new GitHub repository and upload the contents of this folder,
   including the hidden `.github` folder.
2. Open the **Actions** tab, pick **Build unsigned IPA**, press **Run workflow**.
3. When it finishes (~5 min), download the **SolitaireAI-ipa** artifact and
   unzip it to get `SolitaireAI.ipa`.

## 2a. Install straight on the iPhone (recommended — no PC at all)

Your phone is jailbroken with palera1n, so it can install the app itself. No
Apple ID, no Sideloadly, and it never expires.

1. On the phone, open **Sileo** and add the source `https://cydia.akemi.ai/`.
2. Install **AppSync Unified** from that source (this lets the phone run
   unsigned apps).
3. Also install **appinst** (search Sileo) — or use Filza, which can install
   `.ipa` files by tapping them.
4. In Safari on the phone, download `SolitaireAI.ipa` from your GitHub Actions
   run (Actions → the finished run → Artifacts).
5. In **Filza**, go to `/var/mobile/Downloads`, unzip the artifact if needed,
   then tap `SolitaireAI.ipa` → **Install**. (Or in NewTerm:
   `appinst /var/mobile/Downloads/SolitaireAI.ipa`.)
6. The **Solitaire AI** icon appears on your home screen.

## 2b. Install with Sideloadly (Windows) — only if you prefer a PC

1. Plug in the iPhone, open Sideloadly, drop in `SolitaireAI.ipa`.
2. Enter your normal Apple ID (free is fine).
3. In **Advanced options**, tick **Sideload app extensions** so the recorder is
   installed as well, and leave **Enable app groups** unticked.
4. Press Start, then trust the certificate on the phone under
   Settings → General → VPN & Device Management.

## 3. Check the two gates before enabling taps

1. Open **Solitaire AI**, turn **Bot enabled** on, leave **Dry run** on, Save.
   (Leave Server empty unless you host the dashboard yourself.)
2. Tap **Start / stop screen capture**. **Gate 1:** “Solitaire AI Capture”
   appears in the list. If it does not, extensions were not installed — redo
   step 2 with **Sideload app extensions** ticked.
3. Start the broadcast and open your game. **Gate 2:** the status line turns
   green and moves appear in the activity list.

Only after both gates pass, turn **Dry run** off so the jailbreak helper starts
playing the moves.
