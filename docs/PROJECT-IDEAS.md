# Project ideas from the models already on this Mac (1 Oct 2026)

Twelve projects proposed from the local models in place, researched against what each model can actually do and what a Swift app on Apple silicon can practically integrate. Ranked. **#4 became GyozaVitals** (1.0 on 2 Oct, 1.0.9 on 5 Oct). **#3 became Gyozaclikr** (researched and designed 5 Oct, 1.0 to 1.0.10 on 6 Oct; Apple's on-device model takes images on macOS 27, so it leads with Apple Intelligence and keeps Qwen3-VL as the second engine; verified on the Mac: text and image answers from both engines, region capture with Live Text, a conversation in the box, drag, resize, mail through Gmail; 1.1 adds Claude through the signed-in Claude Code CLI as a third, user-chosen engine; 1.1.3 closes the first day at seventeen releases with Replace, Insert below and Claude's web search verified, the owner's verdict "a full app"; 1.1.4 on 7 Oct lets § alone be the shortcut).

## The inventory the list was built from
| Capability | Models | Used by |
|---|---|---|
| Text, tool calling | hermes3:8b (Ollama and a koboldcpp GGUF copy: 9 GB for one model), hermes3:3b | Flow, character-bot |
| Vision and language | Qwen3-VL-8B (abliterated), JoyCaption | Qwen Image prompt helper, character-bot photos |
| Embeddings, reranking | nomic-embed-text, Qwen3-Reranker-0.6B | character-bot only |
| Speech to text | Whisper large-v3-turbo | Flow |
| Image generation and editing | Qwen Image 2.1 + Qwen3-VL encoder + VAE (runs on sd.cpp) | Qwen Image |
| Upscaling | Real-ESRGAN ×4 | Qwen Image |

## Constraints that shape everything
1. **The Mac has 16 GB.** One 8B model at a time; Qwen Image alone fills it. Ollama loads one model at a time by default.
2. **Qwen Image 2.1 is non-commercial** (Qwen Research License) and takes minutes per image on a laptop.
3. Ollama's default context is 4,096 tokens unless an app sets `num_ctx`.

## The twelve, ranked
1. **Screen memory (local "Rewind").** Screenshots → Apple Vision OCR → nomic embeddings in sqlite-vec → reranker → hermes3 answers with the screenshot. Qwen3-VL only for screens OCR can't explain. High difficulty; needs dedup and retention from day one.
2. **GyozaYap: local Ask over all meetings and honest action items.** nomic + reranker for Ask across meetings; hermes3 (128K, grammar-enforced JSON) extracts action items with a quoted transcript line the code verifies. Medium; biggest payoff per hour.
3. **"Ask my screen" Service** (→ Gyozaclikr). Select a region → Qwen3-VL: table to CSV, explain error, translate, read chart, find a button (bounding boxes in 0–1000 coordinates). Low–medium. Downscale to ≤1.5 MP; validate table totals.
4. **GyozaVitals** (done): menu-bar monitor for loaded models and system load.
5. **Photo curator.** JoyCaption + Qwen3-VL captions → embeddings → natural-language search, near-duplicates, Real-ESRGAN on export. Medium; background indexer.
6. **GyozaPortalworks: import a ladder from a screenshot.** Qwen3-VL transcribes a TIA/GX screenshot into the ladder model; the existing CPU simulator verifies it by running it. Medium–high.
7. **Voice-driven desktop agent.** Whisper → hermes3 tool calling → App Intents/AppleScript; Qwen3-VL grounding only when the Accessibility API can't read an app. High; the flakiest.
8. **Receipt and invoice ledger.** Vision OCR + Qwen3-VL with a JSON schema; verify sums. Low–medium; only if there are receipts to process.
9. **Notes and files search** (the simpler sibling of #1): nomic + sqlite-vec + reranker, Spotlight via `CSSearchableIndex`. Medium.
10. **Character-bot: vision and hands.** Abliterated Qwen3-VL for photos with text or several subjects; hermes3 tools. Low–medium, incremental.
11. **Notch image editor** (GyozaIsland + Qwen Image edit mode via ComfyUI/sd.cpp API). Fun demo; minutes per edit; licence.
12. **Consistent-character thumbnail maker** with Qwen Image's reference images. Same caveats as 11.

## Skip
A generic chat UI (exists); speaker diarization on whisper (needs pyannote, CUDA-oriented); anything commercial on Qwen Image 2.1; replacing Flow's whisper with Apple SpeechAnalyzer without benchmarking on the user's own voice.

## Recommended order
#4 (done) → #3 (Gyozaclikr, shipped) → #2 → #1. Do one of 11–12 as a toy, not a product.
