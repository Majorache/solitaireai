# Solitaire AI — flat upload version

All source files sit in the top level of the repository, so you can upload them
with GitHub's "Add file → Upload files" without needing folders.

The only file that MUST live in a folder is the build recipe, because GitHub
only looks for it in one place.

## Steps

1. Upload every file from this folder to your repository (drag them all in at
   once, then press **Commit changes**).
2. In the repo, click **Add file → Create new file**.
3. In the filename box type exactly:
   `.github/workflows/build-ipa.yml`
   (typing the slashes creates the folders for you)
4. Open `build-ipa.yml` from this folder, copy everything inside it, paste it
   into the big text box, and press **Commit changes**.
5. If your repo still has an old plain `Info.plist` or an old `project.yml`
   from a previous upload, open it and delete it — this version uses
   `App-Info.plist` and `Extension-Info.plist` instead.
6. Go to the **Actions** tab → **Build unsigned IPA** → **Run workflow**.
7. When it finishes, download the **SolitaireAI-ipa** artifact.

## Installing on the phone (no PC)

1. In **Sileo**, add the source `https://cydia.akemi.ai/`.
2. Install **AppSync Unified** and **appinst**.
3. Download the artifact in Safari, unzip it, then tap `SolitaireAI.ipa` in
   **Filza** → **Install**.
4. The **Solitaire AI** icon appears on the home screen.

## Two checks before enabling taps

1. Open Solitaire AI → Bot enabled ON, Dry run ON → Save.
2. Tap **Start / stop screen capture** — "Solitaire AI Capture" must appear.
3. Start the broadcast, open your game — status turns green and moves appear.

Only then turn **Dry run** off.
