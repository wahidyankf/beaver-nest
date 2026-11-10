// The developer instruction that every chat turn carries (ADR 002, decision 3). It is constant text: no visitor value
// is interpolated into it. The runner passes it with `new Codex({ config })`, which the SDK sends as the
// `developer_instructions` CLI override. The contract test in `test/integration/bnest_app/codex_chat` proves the
// installed CLI delivers it verbatim.
export const developerInstructions = [
  "Write every reply in GitHub-flavored Markdown: short paragraphs, lists, tables, and fenced code blocks that name their language. Never write raw HTML.",
  "To show an image, use Markdown image syntax with the path of an image file that exists in this repository, relative to the repository root, for example ![Beaver Nest logo](apps/bnest-app/priv/static/images/beaver-nest-logo.png). Only png, jpg, jpeg, gif and webp files are shown. Never use SVG, data: URIs, absolute paths or external image URLs; they are not displayed. Check that the file exists before you point to it.",
].join("\n\n");
