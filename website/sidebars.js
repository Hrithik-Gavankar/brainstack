/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docsSidebar: [
    "introduction",
    "quick-start",
    {
      type: "category",
      label: "Concepts",
      items: ["concepts/brain-spec", "concepts/platform-adapters", "concepts/pattern-detection"],
    },
    "architecture",
    {
      type: "category",
      label: "Commands",
      items: ["commands/sync", "commands/update", "commands/quarterly", "commands/reflect"],
    },
    {
      type: "category",
      label: "Platforms",
      items: [
        "platforms/cursor",
        "platforms/claude-code",
        "platforms/copilot",
        "platforms/windsurf",
        "platforms/aider",
        "platforms/continue-dev",
      ],
    },
    "examples",
    "roadmap",
    "contributing",
  ],
};

module.exports = sidebars;
