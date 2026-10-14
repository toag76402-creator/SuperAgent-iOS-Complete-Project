# SuperAgent safe modification notes

## Applied

- The default API route is OpenRouter Chat Completions: `https://openrouter.ai/api/v1/chat/completions`.
- The fresh-install default model is `google/gemini-2.5-flash`, keeping text and image workflows usable.
- The default system prompt now uses a concise technical simulation/data-processing style.
- API keys remain user-supplied at runtime and are not embedded in the project.
- Existing OpenRouter, Gemini, and custom OpenAI-compatible endpoint support remains available.
- Added unit checks for the new defaults and prompt invariants.

## Intentionally preserved

- Tool argument validation and allow-listing.
- Explicit approval for opening URLs, clipboard writes, and reminder creation.
- Honest reporting of actual tool results.
- iOS sandbox and provisioning requirements.

## Not added

- Private Apple entitlements that are not authorized by a provisioning profile.
- Code that disables safety/approval controls or misrepresents simulated actions as completed actions.
- A provider/model selected specifically to evade service safeguards.

## Build

Run `./build_ipa.sh` on macOS with Xcode and XcodeGen installed. The script creates an unsigned `SuperAgent.ipa`; sign it with your own valid certificate/profile before installation.
