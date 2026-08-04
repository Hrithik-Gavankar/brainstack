# Jordan Park — Engineering Profile

> Last updated: 2026-07-12
> Auto-generated baseline. Updates itself via `engineer-brain update`.

---

## Identity

- **Name:** Jordan Park
- **Role:** Platform Engineer, Developer Experience Team, Enterprise SaaS
- **Total experience:** 6 years
- **Workspace:** ~/platform
- **Primary tools:** Windsurf, Python, Go, Kubernetes, Backstage
- **Career goal:** Staff Platform Engineer / Engineering Manager (undecided)

---

## Career History

### EnterpriseCo — Platform Engineer
**Sep 2023 – Present** (current)

Building the internal developer platform that 400+ engineers use daily. Owns service catalog, CI/CD pipelines, developer portal, and self-service infrastructure.

- Primary codebase: developer-portal (Backstage), platform-cli
- Cross-repo work: ci-pipelines, service-templates, infra-modules
- Key technologies: Python, Go, Kubernetes, Backstage, Crossplane, ArgoCD, PostgreSQL

### MidSize Corp — Backend Engineer
**Mar 2021 – Aug 2023** (2.5 years)

- Built microservices for internal tools platform
- Designed API gateway handling 10K req/s
- Technologies: Python, FastAPI, Docker, Redis, RabbitMQ, AWS

### Consulting Firm — Software Developer
**Jul 2020 – Feb 2021** (8 months)

- Client-facing development across multiple tech stacks
- Technologies: Java, Spring, Angular, PostgreSQL

---

## Full Skills Inventory

### Platform & Infrastructure
| Skill | Proficiency | Where Proven | Last Used |
|-------|------------|--------------|-----------|
| Kubernetes | Strong | EnterpriseCo — platform operator | 2026-07-12 |
| Backstage | Strong | EnterpriseCo — developer portal | 2026-07-12 |
| Crossplane | Growing | EnterpriseCo — infrastructure abstraction | 2026-07-10 |
| ArgoCD | Strong | EnterpriseCo — GitOps | 2026-07-11 |
| Helm | Strong | EnterpriseCo — chart management | 2026-07-09 |

### Backend
| Skill | Proficiency | Where Proven | Last Used |
|-------|------------|--------------|-----------|
| Python | Strong | Both roles | 2026-07-12 |
| Go | Growing | EnterpriseCo — CLI tools, operators | 2026-07-11 |
| FastAPI | Strong | MidSize Corp (dormant) | 2023-08 |
| PostgreSQL | Strong | Both roles | 2026-07-12 |
| Redis | Strong | MidSize Corp + EnterpriseCo | 2026-07-08 |

### Developer Experience
| Skill | Proficiency | Where Proven | Last Used |
|-------|------------|--------------|-----------|
| CLI tool development | Strong | EnterpriseCo — platform-cli | 2026-07-11 |
| Template scaffolding | Strong | EnterpriseCo — service-templates | 2026-07-10 |
| Documentation (docs-as-code) | Strong | EnterpriseCo — TechDocs | 2026-07-12 |
| Golden paths | Growing | EnterpriseCo — service creation flow | 2026-07-08 |

### Underused
- API gateway design — built at scale, could improve platform's ingress story
- RabbitMQ / event-driven patterns — proven expertise, platform uses Kafka instead
- Angular / frontend — consulting background, useful for portal UI improvements

---

## Active Repositories

| Repo | Role | Contribution Level | Last Active | Focus Area |
|------|------|--------------------|-------------|------------|
| developer-portal | Co-owner | Heavy | 2026-07-12 | Backstage plugins |
| platform-cli | Owner | Heavy | 2026-07-11 | Developer CLI |
| service-templates | Owner | Moderate | 2026-07-10 | Cookiecutter templates |
| ci-pipelines | Contributor | Moderate | 2026-07-09 | Reusable workflows |
| infra-modules | Contributor | Light | 2026-07-05 | Crossplane compositions |
| platform-docs | Owner | Moderate | 2026-07-12 | Developer documentation |

---

## Work Patterns

### Commit Type Distribution
```
feat:      40%
fix:       20%
docs:      18%
refactor:  12%
chore:     10%
```

### Velocity Trend
```
2026-07: 38 commits (in progress)
2026-06: 72 commits
2026-05: 68 commits
2026-04: 55 commits
```

### Work Schedule
- **Peak hours:** 10AM–1PM KST, 3PM–6PM KST
- **Active days:** Monday–Friday
- **Deep work windows:** Mornings for Go/Python development, afternoons for platform support

### Implementation Style
1. User-centric: talks to developer users before building
2. CLI-first: every platform capability exposed via CLI before UI
3. Convention over configuration: sensible defaults, escape hatches for power users
4. Metrics-driven: tracks adoption, time-to-production, developer satisfaction

---

## Current Sprint Context

### Active Branches
| Repo | Branch | Status |
|------|--------|--------|
| developer-portal | feat/cost-visibility-plugin | In progress |
| platform-cli | feat/deploy-command-v2 | In review (PR #67) |
| service-templates | feat/python-fastapi-template | In progress |

### Recent Achievements
1. Shipped self-service database provisioning (PR #145) — 200+ DBs created via portal
2. Reduced service creation time from 2 days to 15 minutes with golden path
3. Platform CLI adopted by 85% of engineering org (up from 40% last quarter)

---

## Growth Areas & Feedback Loop

### Strengths to Leverage
- Strong product instincts for internal tools
- Excellent documentation habits (developer-portal docs cited in onboarding)
- Bridge between infra and application teams

### Growth Roadmap

#### Technical Leadership
- [x] Own platform CLI end-to-end (done — 85% adoption)
- [ ] Design multi-tenant platform architecture for acquired company integration
- [ ] Lead platform engineering guild (monthly knowledge sharing)

#### Breadth & Depth
- [ ] Build a Kubernetes operator in Go for custom resource management
- [ ] Implement platform-wide SLO framework
- [x] Ship Crossplane-based self-service infrastructure (done)

#### Influence & Visibility
- [ ] Present at KubeCon or PlatformCon
- [ ] Publish internal platform engineering playbook
- [ ] Mentor 2 engineers transitioning into platform engineering
