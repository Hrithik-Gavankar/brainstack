// @ts-check

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: "Engineer Brain",
  tagline: "A persistent engineering context layer for AI coding assistants.",
  favicon: "img/favicon.ico",

  url: "https://engineer-brain.dev",
  baseUrl: "/",

  organizationName: "Hrithik-Gavankar",
  projectName: "engineer-brain",

  onBrokenLinks: "throw",
  onBrokenMarkdownLinks: "warn",

  i18n: {
    defaultLocale: "en",
    locales: ["en"],
  },

  presets: [
    [
      "classic",
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: "./sidebars.js",
          editUrl:
            "https://github.com/Hrithik-Gavankar/brainstack/tree/main/website/",
        },
        blog: false,
        theme: {
          customCss: "./src/css/custom.css",
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      navbar: {
        title: "Engineer Brain",
        items: [
          {
            type: "docSidebar",
            sidebarId: "docsSidebar",
            position: "left",
            label: "Docs",
          },
          {
            href: "https://github.com/Hrithik-Gavankar/brainstack",
            label: "GitHub",
            position: "right",
          },
        ],
      },
      footer: {
        style: "dark",
        links: [
          {
            title: "Docs",
            items: [
              { label: "Quick Start", to: "/docs/quick-start" },
              { label: "BRAIN.md Spec", to: "/docs/brain-spec" },
              { label: "Architecture", to: "/docs/architecture" },
            ],
          },
          {
            title: "Community",
            items: [
              {
                label: "GitHub Discussions",
                href: "https://github.com/Hrithik-Gavankar/brainstack/discussions",
              },
              {
                label: "Issues",
                href: "https://github.com/Hrithik-Gavankar/brainstack/issues",
              },
            ],
          },
          {
            title: "More",
            items: [
              {
                label: "GitHub",
                href: "https://github.com/Hrithik-Gavankar/brainstack",
              },
              {
                label: "Roadmap",
                to: "/docs/roadmap",
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Hrithik Gavankar. MIT License.`,
      },
      prism: {
        theme: require("prism-react-renderer").themes.github,
        darkTheme: require("prism-react-renderer").themes.dracula,
        additionalLanguages: ["bash", "markdown"],
      },
    }),
};

module.exports = config;
