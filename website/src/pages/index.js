import React from "react";
import clsx from "clsx";
import Link from "@docusaurus/Link";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";
import Layout from "@theme/Layout";

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <header
      className={clsx("hero hero--primary")}
      style={{ textAlign: "center", padding: "4rem 0" }}
    >
      <div className="container">
        <h1 className="hero__title">{siteConfig.title}</h1>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div style={{ display: "flex", gap: "1rem", justifyContent: "center" }}>
          <Link
            className="button button--secondary button--lg"
            to="/docs/quick-start"
          >
            Get Started
          </Link>
          <Link
            className="button button--outline button--lg"
            to="/docs/introduction"
            style={{ color: "white", borderColor: "white" }}
          >
            Learn More
          </Link>
        </div>
      </div>
    </header>
  );
}

const features = [
  {
    title: "Persistent Context",
    description:
      "Your AI loads your full engineering profile on every interaction. No more re-explaining your stack, your repos, or your goals.",
  },
  {
    title: "Self-Updating",
    description:
      "BRAIN.md evolves as you work. It scans your git history and auto-classifies your expertise, detects patterns, and tracks growth.",
  },
  {
    title: "Platform Agnostic",
    description:
      "Same brain across Cursor, Claude Code, Copilot, Windsurf, Aider, and Continue.dev. Switch tools without losing context.",
  },
];

function Feature({ title, description }) {
  return (
    <div className={clsx("col col--4")} style={{ padding: "1rem" }}>
      <div style={{ textAlign: "center" }}>
        <h3>{title}</h3>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function Home() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout title="Home" description={siteConfig.tagline}>
      <HomepageHeader />
      <main>
        <section style={{ padding: "2rem 0" }}>
          <div className="container">
            <div className="row">
              {features.map((props, idx) => (
                <Feature key={idx} {...props} />
              ))}
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
