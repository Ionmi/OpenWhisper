Build app always after changes to prevent errors and warnings.

## Release checklist

After pushing a new version tag and the GitHub Release workflow completes:

1. Get the SHA256 of the new zip: `curl -sL "https://github.com/Ionmi/OpenWhisper/releases/download/<VERSION>/OpenWhisper.zip" | shasum -a 256`
2. Update the Homebrew cask in `Ionmi/homebrew-tap` repo (`Casks/openwhisper.rb`) with the new version and SHA256.
