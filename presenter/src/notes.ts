// Speaker notes for luna.nimit.dev/deck, keyed by each slide's data-title.
// They live here, not in the site, so only someone holding the key can read them.
// Edit, then redeploy: `npx wrangler deploy` from presenter/.
export const NOTES: Record<string, string[]> = {
  "Luna": [
    "Hi, I'm Nimit, and this is Xuan-Quy. We built Luna.",
    "Luna is a screen recorder your AI can read.",
  ],
  "Humans to humans": [
    "When something broke, you turned to a teammate and said: look.",
    "They saw it, they got it, they fixed it.",
  ],
  "Humans to AI": [
    "Now that teammate is an AI agent, and it can't see your screen.",
    "So you type a paragraph, and it asks you three questions back: which page, what did you click, what did you expect.",
  ],
  "Speak like we spoke": [
    "We think you should talk to AI the way you talk to people.",
    "Show it, say it, point at it.",
  ],
  "Readable to AI": [
    "Luna turns all three into one text.",
    "Your voice becomes a transcript, your clicks become numbered steps, and the video path sits on top.",
    "It lands on your clipboard. Paste it into any agent.",
  ],
  "Demo": [
    "Here it is in under a minute.",
    "Press Play below. Switch to Tiếng Việt if the room is mostly Vietnamese.",
    "Chapters: select an area, record, stop, paste.",
  ],
  "MCP": [
    "With MCP, your AI can use Luna directly.",
    "It can start and stop a recording and read the report itself.",
    "Claude, ChatGPT, Cursor, Codex, Gemini CLI, or your own agent.",
  ],
  "ChatGPT plugin": [
    "ChatGPT can't watch video.",
    "So Luna sends it the steps, the transcript and the text on screen.",
    "Upload a recording, then talk it through from your phone.",
  ],
  "Open source": [
    "It's open source, MIT licensed, free, and there's no account.",
    "Read the code, fork it, or open an issue in plain words.",
  ],
  "Platforms": [
    "Mac works today.",
    "Windows is being built in the open, issue #1. If you're on Windows, come find us.",
  ],
  "Our ask": [
    "Three asks: vote for Luna, try it at luna.nimit.dev, and star it on GitHub.",
    "Leave this slide up during questions.",
  ],
};
