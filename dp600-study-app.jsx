import React, { useEffect, useMemo, useState } from "react";

// ---------------------------------------------------------------------------
// Storage helpers
// ---------------------------------------------------------------------------
const STORAGE_KEY = "dp600-drill-stats";

const emptyStats = () => ({
  perCategory: {},
  lastSession: null,
});

async function loadStats() {
  try {
    const raw = await window.storage.get(STORAGE_KEY);
    if (!raw) return emptyStats();
    const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    return { ...emptyStats(), ...parsed };
  } catch {
    return emptyStats();
  }
}

async function saveStats(stats) {
  try {
    await window.storage.set(STORAGE_KEY, JSON.stringify(stats));
  } catch {
    /* swallow — still function without persistence */
  }
}

async function clearStats() {
  try {
    await window.storage.set(STORAGE_KEY, JSON.stringify(emptyStats()));
  } catch {
    /* ignore */
  }
}

// ---------------------------------------------------------------------------
// Category metadata
// ---------------------------------------------------------------------------
const CATEGORIES = [
  {
    id: "security-scope",
    name: "Security Scope Word Identification",
    guidance:
      "Focus on multi-select questions (pick 2-3). The question should mix controls from different security layers. Include at least one distractor from the wrong granularity (e.g., workspace role when the answer is data-level). Use scope keywords like 'data elements,' 'specific rows,' 'must NOT access other items,' 'objects within warehouse.'",
  },
  {
    id: "query-folding",
    name: "Query Folding Step Ordering",
    guidance:
      "Present a sequence of Power Query applied steps and ask which fix restores query folding or resolves a timeout. Include Table.Buffer and Enable Staging as distractors. The correct answer should involve reordering steps.",
  },
  {
    id: "append-replace",
    name: "Dataflow Gen2 Append vs Replace",
    guidance:
      "Describe a data source with specific characteristics (transient daily files vs cumulative extracts) and ask which Dataflow Gen2 destination refresh setting to use. Include incremental refresh as a distractor — it's a semantic model feature, not a Dataflow Gen2 setting.",
  },
  {
    id: "column-profiling",
    name: "Column Quality vs Profile vs Distribution",
    guidance:
      "Describe a specific data quality investigation need and ask which profiling feature (column quality, column profile, or column distribution) provides the required information. Use the precise keywords: 'percentage of valid' → quality, 'statistics' → profile, 'frequency/uniqueness' → distribution.",
  },
  {
    id: "eventhouse-onelake",
    name: "Eventhouse OneLake Integration",
    guidance:
      "Ask how to make Eventhouse data accessible to other Fabric workloads. Include 'add another Eventstream output' as a distractor. The answer is enabling OneLake availability on the KQL database.",
  },
  {
    id: "shortcut-arch",
    name: "Shortcut as Simplest Architecture",
    guidance:
      "Present a scenario where data is in external cloud storage (ADLS Gen2, S3) and the requirement emphasises minimal effort/duplication. Include over-engineered options (Warehouse + cross-database, Pipeline + copy). The answer should be a Lakehouse with a shortcut.",
  },
  {
    id: "bpa-vertipaq",
    name: "BPA vs VertiPaq Analyzer",
    guidance:
      "Ask about auditing a model for design issues OR analysing memory consumption. Use keywords: 'audit/identify/resolve' → BPA, 'memory/compression/size' → VertiPaq. Include Performance Analyzer and DAX Studio as distractors.",
  },
  {
    id: "apply-buttons",
    name: "Apply Buttons for DirectQuery Optimisation",
    guidance:
      "Describe a DirectQuery report with excessive queries during slicer interaction. Include Top N filters and aggregation tables as distractors. The answer is enabling apply buttons.",
  },
  {
    id: "direct-lake",
    name: "Direct Lake as Default for Lakehouse/Warehouse",
    guidance:
      "Place data in a Fabric Lakehouse or Warehouse and ask for the best storage mode emphasising performance. Include DirectQuery and Import as distractors. Direct Lake is the answer when data is in OneLake.",
  },
];

// ---------------------------------------------------------------------------
// Seed question bank
// ---------------------------------------------------------------------------
const SEED_QUESTIONS = {
  "security-scope": [
    {
      question:
        "A Fabric analytics team needs to ensure that sales managers can only see revenue data for their own region when viewing reports. The semantic model is published to a workspace where managers have the Viewer role. Which two actions should you take?",
      multiSelect: true,
      selectCount: 2,
      options: [
        { label: "A", text: "Assign managers to the Contributor workspace role" },
        { label: "B", text: "Define row-level security roles with DAX filters on the Region column" },
        { label: "C", text: "Apply column-level security using Tabular Editor" },
        { label: "D", text: "Add managers to RLS roles in the semantic model" },
        { label: "E", text: "Share the report using item-level permissions with Build access" },
      ],
      correct: ["B", "D"],
      explanation:
        "The question says 'only see revenue data for their own region' — this is row-level filtering. B creates the RLS role with the DAX filter, D assigns the users to that role. Contributor role (A) would bypass RLS entirely. CLS (C) hides columns, not rows. Item-level Build access (E) controls whether they can build new reports, not what data they see.",
    },
    {
      question:
        "Your organisation's data warehouse contains HR salary data. You need to ensure that HR analysts can query the warehouse but cannot see the Salary and NationalInsuranceNumber columns. Which action should you take?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Create a row-level security policy filtering out salary rows" },
        { label: "B", text: "Use T-SQL DENY on the Salary and NationalInsuranceNumber columns for the analyst role" },
        { label: "C", text: "Apply sensitivity labels to the columns" },
        { label: "D", text: "Configure column-level security via T-SQL GRANT, excluding the restricted columns" },
        { label: "E", text: "Remove the columns from the default semantic model" },
      ],
      correct: ["D"],
      explanation:
        "'Cannot see specific columns' = column-level security. CLS in a Fabric Warehouse is implemented via T-SQL GRANT/DENY at the column level (B and D both work; D is the canonical positive-grant pattern). RLS (A) filters rows, not columns. Sensitivity labels (C) classify data for governance but don't restrict query access. Removing from the semantic model (E) only hides from reports, not from direct SQL queries.",
    },
    {
      question:
        "A government contractor requires that when reports are exported from Fabric and shared externally, the data classifications travel with the exported files. Additionally, within the workspace, some reports must be restricted to specific teams, and within those reports, executives should see all regions while regional managers see only their own. Which three controls should you implement?",
      multiSelect: true,
      selectCount: 3,
      options: [
        { label: "A", text: "Workspace roles to restrict by team" },
        { label: "B", text: "Sensitivity labels for export classification" },
        { label: "C", text: "Item-level sharing for team-specific reports" },
        { label: "D", text: "Row-level security for regional filtering" },
        { label: "E", text: "Dynamic data masking on the SQL endpoint" },
      ],
      correct: ["B", "C", "D"],
      explanation:
        "Three different scope layers are asked for simultaneously. 'Classifications travel with exports' = sensitivity labels (B). 'Some reports restricted to specific teams' — if only some reports, you cannot use workspace roles (A), because workspace Viewer gives access to ALL items. Use item-level sharing (C). 'Executives see all, regional managers see their own' = RLS (D). DDM (E) masks display values at the SQL layer, not in reports.",
    },
  ],
  "query-folding": [
    {
      question:
        "A Dataflow Gen2 connects to an Azure SQL Database. The applied steps are: (1) Source, (2) Split Column by Position, (3) Filter rows where Status = 'Active', (4) Select columns. The dataflow is running slowly. You check the query folding indicators and see that steps 3 and 4 are not folding. What should you do?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Add a Table.Buffer step after the Source step" },
        { label: "B", text: "Move the Filter and Select steps before the Split Column by Position step" },
        { label: "C", text: "Convert the dataflow to a Notebook" },
        { label: "D", text: "Enable staging in the dataflow settings" },
      ],
      correct: ["B"],
      explanation:
        "Split Column by Position is a non-foldable operation. Once a non-foldable step appears, all subsequent steps also lose folding. Moving the foldable steps (Filter, Select) before the non-foldable step (Split) restores folding for those operations. Table.Buffer (A) caches data in memory and prevents all downstream folding — the opposite of what you want. Converting to a Notebook (C) abandons the dataflow entirely. Staging (D) improves performance via Spark but doesn't fix the folding issue within the Power Query engine.",
    },
    {
      question:
        "You are building a Dataflow Gen2 that loads supplier data from a SQL Server source. Your steps are: (1) Source, (2) Add Index Column, (3) Group By supplier region, (4) Filter to regions with more than 100 suppliers. A colleague reports that the query is timing out. Which fix most directly addresses the timeout?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Enable staging for the query" },
        { label: "B", text: "Split into a staging dataflow (Source + Filter + Group By) and a transformation dataflow (Add Index Column)" },
        { label: "C", text: "Move the Group By and Filter steps before the Add Index Column step" },
        { label: "D", text: "Increase the dataflow timeout setting" },
      ],
      correct: ["C"],
      explanation:
        "Add Index Column always breaks query folding. Group By and Filter are foldable. Reordering so that foldable operations execute before the folding-breaking step allows the database to handle filtering and aggregation server-side. Option B would also work but is more complex — C is the most direct fix. Staging (A) helps but doesn't address the root cause. There is no configurable timeout setting (D) that fixes a folding problem.",
    },
  ],
  "append-replace": [
    {
      question:
        "A logistics company receives a daily CSV file from a carrier partner. Each day's file contains only that day's shipments — previous days are not included in subsequent files. The data must be loaded into a Fabric Lakehouse table where analysts query historical trends across months. You use Dataflow Gen2 to ingest the file. What refresh setting should you configure on the Dataflow Gen2 destination?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Replace (default)" },
        { label: "B", text: "Append" },
        { label: "C", text: "Incremental refresh" },
        { label: "D", text: "Full refresh with partition management" },
      ],
      correct: ["B"],
      explanation:
        "The source is transient — each day's file replaces the previous one. If you use Replace (A), each refresh overwrites the Lakehouse table with only today's data, destroying history. Append (B) adds each day's rows to the existing table, preserving the historical record. Incremental refresh (C) is a semantic model feature for Import mode partitioning — it's a different tool at a different layer. Partition management (D) is not a Dataflow Gen2 destination setting.",
    },
    {
      question:
        "A data team loads weekly sales summaries into a Lakehouse. The source system provides a complete, cumulative dataset each week — every weekly extract contains all historical records. The Dataflow Gen2 destination is currently set to Append. Analysts report duplicate records appearing in their reports. What should you change?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Add a deduplication step in the Dataflow Gen2" },
        { label: "B", text: "Change the destination setting to Replace" },
        { label: "C", text: "Implement incremental refresh on the semantic model" },
        { label: "D", text: "Add a primary key constraint to the Lakehouse table" },
      ],
      correct: ["B"],
      explanation:
        "The source is cumulative (contains all records each time). Append mode adds every row from every refresh, duplicating all previously loaded records. Replace mode overwrites the table with each refresh, which is correct when the source is complete. Deduplication (A) would work but adds unnecessary complexity when the correct setting solves it directly. Incremental refresh (C) is for semantic models, not Dataflow Gen2 destinations. Lakehouse Delta tables don't support primary key constraints for deduplication (D).",
    },
  ],
  "column-profiling": [
    {
      question:
        "You open a Dataflow Gen2 and need to quickly identify what percentage of records in the CustomerEmail column contain valid values versus errors or empty cells. Which Power Query data profiling feature should you enable?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Column quality" },
        { label: "B", text: "Column profile" },
        { label: "C", text: "Column distribution" },
        { label: "D", text: "Data type detection" },
      ],
      correct: ["A"],
      explanation:
        "Column quality shows the percentage breakdown of valid, error, and empty values — exactly what's asked. Column profile (B) shows statistics like min, max, mean, and distinct count. Column distribution (C) shows value frequency histograms.",
    },
    {
      question:
        "You need to determine the number of distinct supplier names and the number of unique (appearing only once) supplier names in a Dataflow Gen2 query. Which profiling feature provides this?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Column quality" },
        { label: "B", text: "Column profile" },
        { label: "C", text: "Column distribution" },
        { label: "D", text: "Schema view" },
      ],
      correct: ["C"],
      explanation:
        "Column distribution shows distinct count and unique count (values appearing exactly once), displayed as a frequency histogram. Column profile (B) shows distinct count but also includes statistical measures — it's for 'statistics.' Column quality (A) shows valid/error/empty percentages.",
    },
  ],
  "eventhouse-onelake": [
    {
      question:
        "Your team ingests IoT telemetry data from Azure Event Hubs into a Fabric Eventhouse using an Eventstream. A data analyst wants to query this telemetry data from a Lakehouse notebook using Spark. What should you do to make the Eventhouse data accessible?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Create an additional Eventstream output to the Lakehouse" },
        { label: "B", text: "Enable OneLake availability on the KQL database" },
        { label: "C", text: "Create a shortcut from the Lakehouse to the Eventhouse" },
        { label: "D", text: "Export the KQL database to Parquet files in OneLake" },
      ],
      correct: ["B"],
      explanation:
        "Enabling OneLake availability on the KQL database makes Eventhouse data accessible to other Fabric items (Lakehouses, Warehouses, Notebooks) through OneLake. The Eventstream handles ingestion into the Eventhouse — adding another output (A) creates a separate copy, not integration. Shortcuts (C) don't connect to Eventhouse KQL databases. Manual export (D) defeats the purpose of integrated real-time data.",
    },
  ],
  "shortcut-arch": [
    {
      question:
        "An analytics team needs to query CSV files stored in an external Azure Data Lake Storage Gen2 account. The requirement states 'minimise data duplication and administrative overhead.' The data does not need transformation before analysis. Which approach should you recommend?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Use a Copy Activity pipeline to load the data into a Lakehouse, then query via the SQL analytics endpoint" },
        { label: "B", text: "Create a Lakehouse with a shortcut pointing to the ADLS Gen2 location" },
        { label: "C", text: "Set up a Dataflow Gen2 to transform and load the data into a Warehouse" },
        { label: "D", text: "Create both a Lakehouse and a Warehouse with cross-database querying" },
      ],
      correct: ["B"],
      explanation:
        "A shortcut virtualises external data in OneLake without copying it — minimising both duplication and admin effort. Copy Activity (A) physically moves data, creating duplication. Dataflow Gen2 (C) adds transformation overhead that wasn't required. Cross-database querying (D) over-engineers the solution with unnecessary components.",
    },
  ],
  "bpa-vertipaq": [
    {
      question:
        "You connect to a semantic model using Tabular Editor via the XMLA endpoint. You want to audit the model for design issues such as tables without relationships, measures not in display folders, and columns with excessive cardinality. Which Tabular Editor feature should you use?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "VertiPaq Analyzer" },
        { label: "B", text: "Best Practices Analyzer" },
        { label: "C", text: "Data Preview" },
        { label: "D", text: "Dependency View" },
      ],
      correct: ["B"],
      explanation:
        "Best Practices Analyzer (BPA) audits a model against configurable design rules — relationships, naming conventions, formatting, cardinality warnings. The keyword is 'audit' and 'identify design issues.' VertiPaq Analyzer (A) examines memory consumption and compression statistics — it tells you how much space tables and columns use, not whether the design follows best practices.",
    },
    {
      question:
        "A semantic model is consuming significantly more memory than expected on the Fabric capacity. You need to identify which tables and columns are using the most memory and whether compression is effective. Which tool should you use?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Performance Analyzer in Power BI Desktop" },
        { label: "B", text: "Best Practices Analyzer in Tabular Editor" },
        { label: "C", text: "VertiPaq Analyzer in Tabular Editor" },
        { label: "D", text: "DAX Studio query plan" },
      ],
      correct: ["C"],
      explanation:
        "VertiPaq Analyzer provides detailed memory and compression statistics per table and column — exactly what you need for memory analysis. BPA (B) audits design rules, not memory usage. Performance Analyzer (A) measures visual rendering time in reports. DAX Studio (D) analyses query execution, not storage.",
    },
  ],
  "apply-buttons": [
    {
      question:
        "Users of a DirectQuery report complain that the report feels sluggish. You investigate and find that each time a user adjusts a slicer, multiple queries are sent to the source database before the user has finished making their selections. What should you do to reduce unnecessary queries?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Add Top N filtering to the slicers" },
        { label: "B", text: "Enable apply buttons on the slicer filters" },
        { label: "C", text: "Switch the storage mode to Import" },
        { label: "D", text: "Add aggregation tables to the model" },
      ],
      correct: ["B"],
      explanation:
        "Apply buttons pause query execution until the user clicks 'Apply' after making all slicer selections. This prevents the intermediate queries fired with each individual slicer change. Top N (A) limits the number of values shown but doesn't reduce per-interaction query count. Import (C) solves the problem but abandons real-time freshness. Aggregations (D) improve query speed but don't reduce query count during slicer interaction.",
    },
  ],
  "direct-lake": [
    {
      question:
        "A Fabric Lakehouse contains 50GB of Delta tables refreshed nightly via a Pipeline. You need to build a semantic model that provides fast query performance for Power BI reports. The data team values performance and will accept data that is at most a few hours stale. Which storage mode should you choose?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "Import with scheduled refresh" },
        { label: "B", text: "DirectQuery to the Lakehouse SQL analytics endpoint" },
        { label: "C", text: "Direct Lake" },
        { label: "D", text: "Composite model with Import aggregations and DirectQuery detail" },
      ],
      correct: ["C"],
      explanation:
        "Data is in a Fabric Lakehouse (OneLake), the requirement emphasises performance, and staleness of a few hours is acceptable. Direct Lake reads Delta Parquet directly into the VertiPaq engine — combining DirectQuery-level freshness with Import-level performance. Import (A) would also work but requires scheduled refresh processing and doubles storage. DirectQuery (B) works but is slower for large datasets. A composite model (D) adds unnecessary complexity when Direct Lake handles both needs.",
    },
    {
      question:
        "You are choosing a storage mode for a semantic model. The source data is in a Fabric Warehouse that refreshes every 4 hours. Reports must respond quickly and reflect the most recent Warehouse refresh. Which storage mode should you select?",
      multiSelect: false,
      selectCount: 1,
      options: [
        { label: "A", text: "DirectQuery" },
        { label: "B", text: "Direct Lake" },
        { label: "C", text: "Import with 4-hour incremental refresh" },
        { label: "D", text: "Dual mode" },
      ],
      correct: ["B"],
      explanation:
        "Data in a Fabric Warehouse (OneLake) + performance + freshness = Direct Lake. Direct Lake framing picks up new data within seconds of a Warehouse refresh completing. DirectQuery (A) queries the SQL analytics endpoint live but is slower. Import (C) requires processing time for each refresh and incremental refresh configuration. Dual (D) is a table-level mode within composite models, not a model-level storage choice.",
    },
  ],
};

// ---------------------------------------------------------------------------
// Frameworks data
// ---------------------------------------------------------------------------
const FRAMEWORKS = [
  {
    id: "tool-selection",
    title: "Tool Selection (Ingestion / Transformation)",
    intro: [
      "Pre-selection decision tree:",
      "1. Does data need to physically move? No → Shortcut. Yes → continue.",
      "2. Does data need transformation? No → Copy Activity (or Copy Job if simple). Yes → continue.",
      "3. How large is the data? Large + Lakehouse → Notebooks. Small/medium → Dataflow Gen2.",
    ],
    columns: ["Scenario", "Tool", "Kill-Switch Keywords"],
    rows: [
      ["Large volume, no transformation, highest throughput", "Copy Activity (Pipeline)", "\"1TB,\" \"bulk,\" \"migrate,\" \"most performant\""],
      ["Large volume, no transformation, simple standalone", "Copy Job", "\"simple,\" \"wizard-driven,\" \"no orchestration\""],
      ["Small-medium, transformation needed, low-code", "Dataflow Gen2", "\"clean,\" \"validate,\" \"transform,\" \"code-free\""],
      ["Large data, complex transformation, Lakehouse", "Notebooks (Spark)", "\"large dataset,\" \"complex logic,\" \"ETL in lakehouse\""],
      ["Combine across warehouses, no movement", "Cross-database querying", "\"minimise data movement,\" \"two warehouses\""],
      ["Analyse warehouse data, no code", "Visual query editor", "\"analyse,\" \"no code,\" \"within warehouse\""],
      ["File storage (ADLS, S3, GCS), no copy", "OneLake Shortcut", "\"minimise costs,\" \"virtualise,\" \"not decommissioning\""],
      ["Database engine (Azure SQL, Cosmos DB, SQL Server 2022+)", "Database Mirroring", "\"continuous replication,\" \"near real-time,\" supported DB"],
      ["Streaming (Event Hub, IoT Hub, Kafka)", "Eventstream → Eventhouse", "\"sub-second,\" \"streaming,\" \"real-time telemetry\""],
    ],
    rules: [],
  },
  {
    id: "storage-mode",
    title: "Storage Mode Selection",
    intro: [],
    columns: ["Data Location", "Requirement", "Storage Mode"],
    rows: [
      ["OneLake (Lakehouse/Warehouse)", "Freshness + performance", "Direct Lake"],
      ["OneLake", "Complex Power Query + mixed sources", "Import"],
      ["External database", "Real-time freshness", "DirectQuery"],
      ["External database", "Performance > freshness, batch updates", "Import"],
      ["Composite: fact table", "Too large to import", "DirectQuery"],
      ["Composite: aggregation table", "Must serve from cache", "Import (always)"],
      ["Composite: dimension table", "Must work with both source groups", "Dual"],
    ],
    rules: [],
  },
  {
    id: "security-layer",
    title: "Security Layer",
    intro: [],
    columns: ["Scope Word in Question", "Layer", "Tools"],
    rows: [
      ["\"workspace\" / \"all items\" / \"team\"", "Workspace", "Workspace roles (Admin/Member/Contributor/Viewer)"],
      ["\"specific item\" / \"must NOT access other items\"", "Item", "Item sharing (Read, ReadAll, Build, Reshare)"],
      ["\"specific objects in warehouse\" / \"tables/views\"", "Object", "T-SQL GRANT/DENY + OLS"],
      ["\"specific rows\" / \"data based on role\"", "Row", "RLS (DAX filter or T-SQL policy)"],
      ["\"specific columns\" / \"sensitive columns\"", "Column", "CLS (T-SQL GRANT or Tabular Editor)"],
      ["\"hide tables from metadata\"", "Object visibility", "OLS (Tabular Editor via XMLA)"],
      ["\"mask values\" / \"obfuscate\"", "Display masking", "DDM (SQL endpoint only)"],
      ["\"exports\" / \"compliance\" / \"data leaves Fabric\"", "Export/transit", "Sensitivity labels"],
      ["\"external partners\" / \"outside organisation\"", "Distribution", "Power BI App + RLS + Fixed identity"],
    ],
    rules: [
      "RLS only enforced for Viewer role. Admin/Member/Contributor bypass it.",
      "\"Must NOT access other items\" = never use workspace roles.",
      "Workspace Viewer = access to ALL items in workspace.",
    ],
  },
];

// ---------------------------------------------------------------------------
// AI question generation
// ---------------------------------------------------------------------------
const AI_SYSTEM_TEMPLATE = (categoryName, guidance) => `You are a Microsoft DP-600 exam question generator. Generate ONE multiple-choice question for the category: ${categoryName}.

Rules:
- Use realistic Microsoft Fabric scenarios (enterprise data teams, analytics projects)
- Include 4-5 answer options labelled A through E
- For multi-select questions, state how many to pick
- Include plausible distractors that represent common exam mistakes
- After the options, include the correct answer(s) and a concise explanation of why each distractor is wrong

Category-specific guidance:
${guidance}

Respond ONLY in this JSON format, no markdown fences:
{"question": "...", "multiSelect": false, "selectCount": 1, "options": [{"label": "A", "text": "..."}, ...], "correct": ["A"], "explanation": "..."}`;

function stripFences(s) {
  return s
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
}

async function fetchAIQuestion(category) {
  const prompt = AI_SYSTEM_TEMPLATE(category.name, category.guidance);
  const raw = await window.claude.complete(prompt);
  const cleaned = stripFences(raw);
  const parsed = JSON.parse(cleaned);
  if (!parsed.question || !Array.isArray(parsed.options) || !Array.isArray(parsed.correct)) {
    throw new Error("Malformed AI response");
  }
  return parsed;
}

// ---------------------------------------------------------------------------
// Styling
// ---------------------------------------------------------------------------
const palette = {
  bg: "#0f1115",
  surface: "#161a21",
  surfaceAlt: "#1c2128",
  border: "#262c36",
  text: "#d6dae0",
  textDim: "#8a93a3",
  accent: "#7aa6c2",
  accentDim: "#3f5566",
  good: "#7fb37f",
  bad: "#c47878",
  warn: "#c9a96a",
};

const mono =
  "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace";
const sans =
  "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

const styles = {
  shell: {
    minHeight: "100vh",
    background: palette.bg,
    color: palette.text,
    fontFamily: sans,
    padding: "24px 20px 64px",
  },
  container: { maxWidth: 960, margin: "0 auto" },
  header: { display: "flex", alignItems: "baseline", justifyContent: "space-between", marginBottom: 12 },
  title: { fontFamily: mono, fontSize: 18, letterSpacing: 0.5, margin: 0 },
  subtitle: { fontFamily: mono, fontSize: 12, color: palette.textDim },
  summary: {
    display: "flex",
    gap: 16,
    flexWrap: "wrap",
    padding: "10px 14px",
    background: palette.surface,
    border: `1px solid ${palette.border}`,
    borderRadius: 6,
    fontFamily: mono,
    fontSize: 12,
    marginBottom: 20,
    alignItems: "center",
  },
  summaryItem: { color: palette.textDim },
  summaryValue: { color: palette.text },
  resetBtn: {
    marginLeft: "auto",
    background: "transparent",
    color: palette.textDim,
    border: `1px solid ${palette.border}`,
    padding: "4px 10px",
    fontFamily: mono,
    fontSize: 11,
    cursor: "pointer",
    borderRadius: 4,
  },
  tabs: {
    display: "flex",
    gap: 2,
    borderBottom: `1px solid ${palette.border}`,
    marginBottom: 20,
  },
  tab: (active) => ({
    background: "transparent",
    border: "none",
    borderBottom: `2px solid ${active ? palette.accent : "transparent"}`,
    color: active ? palette.text : palette.textDim,
    padding: "8px 16px",
    fontFamily: mono,
    fontSize: 13,
    cursor: "pointer",
  }),
  grid: { display: "grid", gap: 10, gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))" },
  card: {
    background: palette.surface,
    border: `1px solid ${palette.border}`,
    borderRadius: 6,
    padding: "12px 14px",
    cursor: "pointer",
    transition: "border-color 120ms ease",
  },
  cardName: { fontFamily: mono, fontSize: 13, color: palette.text, marginBottom: 6 },
  badge: { fontFamily: mono, fontSize: 11, color: palette.textDim },
  questionBox: {
    background: palette.surface,
    border: `1px solid ${palette.border}`,
    borderRadius: 6,
    padding: 18,
    marginBottom: 16,
  },
  questionText: { fontFamily: mono, fontSize: 14, lineHeight: 1.6, color: palette.text, whiteSpace: "pre-wrap" },
  selectHint: { fontFamily: mono, fontSize: 11, color: palette.warn, marginTop: 8 },
  optionRow: (selected, revealed, isCorrect, isUserPick) => ({
    display: "flex",
    alignItems: "flex-start",
    gap: 10,
    padding: "8px 10px",
    margin: "6px 0",
    border: `1px solid ${
      revealed
        ? isCorrect
          ? palette.good
          : isUserPick
          ? palette.bad
          : palette.border
        : selected
        ? palette.accent
        : palette.border
    }`,
    borderRadius: 4,
    cursor: revealed ? "default" : "pointer",
    background: revealed && isCorrect ? "rgba(127,179,127,0.08)" : "transparent",
    fontFamily: mono,
    fontSize: 13,
  }),
  optionLabel: { color: palette.accent, minWidth: 18 },
  primary: {
    background: palette.accentDim,
    color: palette.text,
    border: `1px solid ${palette.accent}`,
    padding: "8px 16px",
    fontFamily: mono,
    fontSize: 12,
    cursor: "pointer",
    borderRadius: 4,
  },
  ghost: {
    background: "transparent",
    color: palette.text,
    border: `1px solid ${palette.border}`,
    padding: "8px 16px",
    fontFamily: mono,
    fontSize: 12,
    cursor: "pointer",
    borderRadius: 4,
  },
  result: (correct) => ({
    fontFamily: mono,
    fontSize: 12,
    color: correct ? palette.good : palette.bad,
    marginTop: 12,
    fontWeight: 600,
  }),
  explanation: {
    fontFamily: mono,
    fontSize: 12,
    color: palette.textDim,
    marginTop: 8,
    padding: 12,
    background: palette.surfaceAlt,
    borderLeft: `2px solid ${palette.accent}`,
    lineHeight: 1.6,
  },
  framework: {
    background: palette.surface,
    border: `1px solid ${palette.border}`,
    borderRadius: 6,
    marginBottom: 10,
    overflow: "hidden",
  },
  fwHeader: {
    width: "100%",
    background: "transparent",
    border: "none",
    color: palette.text,
    textAlign: "left",
    padding: "12px 16px",
    fontFamily: mono,
    fontSize: 13,
    cursor: "pointer",
    display: "flex",
    justifyContent: "space-between",
  },
  fwBody: { padding: "0 16px 16px", fontFamily: mono, fontSize: 12, color: palette.text },
  table: { width: "100%", borderCollapse: "collapse", marginTop: 10 },
  th: {
    textAlign: "left",
    padding: "6px 8px",
    borderBottom: `1px solid ${palette.border}`,
    color: palette.textDim,
    fontWeight: 600,
    fontSize: 11,
    textTransform: "uppercase",
    letterSpacing: 0.5,
  },
  td: { padding: "6px 8px", borderBottom: `1px solid ${palette.border}`, color: palette.text, verticalAlign: "top" },
  intro: { color: palette.textDim, lineHeight: 1.6, margin: "10px 0" },
  rules: { marginTop: 14, padding: 12, background: palette.surfaceAlt, borderLeft: `2px solid ${palette.warn}` },
  ruleHead: { color: palette.warn, fontSize: 11, marginBottom: 6, textTransform: "uppercase", letterSpacing: 0.5 },
  loading: { fontFamily: mono, fontSize: 12, color: palette.textDim, padding: 20, textAlign: "center" },
  error: { fontFamily: mono, fontSize: 12, color: palette.bad, padding: 12, background: palette.surfaceAlt, border: `1px solid ${palette.bad}`, borderRadius: 4 },
  back: { background: "transparent", color: palette.textDim, border: "none", fontFamily: mono, fontSize: 11, cursor: "pointer", marginBottom: 12, padding: 0 },
};

// ---------------------------------------------------------------------------
// Derived stats helpers
// ---------------------------------------------------------------------------
function categoryStats(stats, id) {
  const v = stats.perCategory?.[id] || { correct: 0, total: 0 };
  return v;
}

function overallAccuracy(stats) {
  let correct = 0;
  let total = 0;
  for (const id of Object.keys(stats.perCategory || {})) {
    correct += stats.perCategory[id].correct || 0;
    total += stats.perCategory[id].total || 0;
  }
  if (total === 0) return null;
  return { correct, total, pct: Math.round((correct / total) * 100) };
}

function weakestCategory(stats) {
  let worst = null;
  for (const cat of CATEGORIES) {
    const v = categoryStats(stats, cat.id);
    if (v.total === 0) continue;
    const pct = v.correct / v.total;
    if (worst === null || pct < worst.pct) {
      worst = { id: cat.id, name: cat.name, pct };
    }
  }
  return worst;
}

function arraysSameSet(a, b) {
  if (a.length !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------
function SummaryBar({ stats, onReset }) {
  const overall = overallAccuracy(stats);
  const weakest = weakestCategory(stats);
  return (
    <div style={styles.summary}>
      <span style={styles.summaryItem}>
        accuracy:{" "}
        <span style={styles.summaryValue}>
          {overall ? `${overall.pct}% (${overall.correct}/${overall.total})` : "—"}
        </span>
      </span>
      <span style={styles.summaryItem}>
        weakest:{" "}
        <span style={styles.summaryValue}>
          {weakest ? `${weakest.name} (${Math.round(weakest.pct * 100)}%)` : "—"}
        </span>
      </span>
      <span style={styles.summaryItem}>
        last session:{" "}
        <span style={styles.summaryValue}>
          {stats.lastSession ? new Date(stats.lastSession).toLocaleDateString() : "—"}
        </span>
      </span>
      <button
        style={styles.resetBtn}
        onClick={() => {
          if (window.confirm("Reset all progress? This cannot be undone.")) onReset();
        }}
      >
        reset progress
      </button>
    </div>
  );
}

function CategoryGrid({ stats, onPick }) {
  return (
    <div style={styles.grid}>
      {CATEGORIES.map((cat) => {
        const v = categoryStats(stats, cat.id);
        const pct = v.total ? Math.round((v.correct / v.total) * 100) : null;
        return (
          <div
            key={cat.id}
            style={styles.card}
            onClick={() => onPick(cat)}
            onMouseEnter={(e) => (e.currentTarget.style.borderColor = palette.accent)}
            onMouseLeave={(e) => (e.currentTarget.style.borderColor = palette.border)}
          >
            <div style={styles.cardName}>{cat.name}</div>
            <div style={styles.badge}>
              {v.total ? `${v.correct}/${v.total} — ${pct}%` : "no attempts"}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function QuestionView({ q, onAnswered, onNext, onExit, sourceLabel }) {
  const [selected, setSelected] = useState([]);
  const [revealed, setRevealed] = useState(false);
  const [isCorrect, setIsCorrect] = useState(false);

  const multi = q.multiSelect;
  const selectCount = q.selectCount || 1;

  const toggle = (label) => {
    if (revealed) return;
    if (multi) {
      setSelected((prev) =>
        prev.includes(label) ? prev.filter((x) => x !== label) : [...prev, label]
      );
    } else {
      setSelected([label]);
    }
  };

  const canSubmit = multi ? selected.length === selectCount : selected.length === 1;

  const submit = () => {
    const correct = arraysSameSet(selected, q.correct);
    setIsCorrect(correct);
    setRevealed(true);
    onAnswered(correct);
  };

  return (
    <div>
      <button style={styles.back} onClick={onExit}>
        ← back to categories
      </button>
      <div style={styles.questionBox}>
        <div style={{ ...styles.badge, marginBottom: 10 }}>{sourceLabel}</div>
        <div style={styles.questionText}>{q.question}</div>
        {multi && (
          <div style={styles.selectHint}>
            Pick {selectCount}.{" "}
            {selected.length > 0 && (
              <span style={{ color: palette.textDim }}>
                ({selected.length}/{selectCount} selected)
              </span>
            )}
          </div>
        )}
        <div style={{ marginTop: 14 }}>
          {q.options.map((opt) => {
            const isUserPick = selected.includes(opt.label);
            const isCorrectAns = q.correct.includes(opt.label);
            return (
              <div
                key={opt.label}
                style={styles.optionRow(isUserPick, revealed, isCorrectAns, isUserPick)}
                onClick={() => toggle(opt.label)}
              >
                <span style={styles.optionLabel}>{opt.label}.</span>
                <span>{opt.text}</span>
              </div>
            );
          })}
        </div>
        {!revealed && (
          <div style={{ marginTop: 16 }}>
            <button
              style={canSubmit ? styles.primary : { ...styles.primary, opacity: 0.4, cursor: "not-allowed" }}
              onClick={canSubmit ? submit : undefined}
              disabled={!canSubmit}
            >
              submit
            </button>
          </div>
        )}
        {revealed && (
          <>
            <div style={styles.result(isCorrect)}>
              {isCorrect ? "✓ correct" : `✗ incorrect — answer: ${q.correct.join(", ")}`}
            </div>
            <div style={styles.explanation}>{q.explanation}</div>
            <div style={{ marginTop: 14, display: "flex", gap: 10 }}>
              <button style={styles.primary} onClick={onNext}>
                next question
              </button>
              <button style={styles.ghost} onClick={onExit}>
                done
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function DrillMode({ stats, onUpdateStats }) {
  const [category, setCategory] = useState(null);
  const [mode, setMode] = useState(null); // "fixed" | "ai" | null
  const [fixedIdx, setFixedIdx] = useState(0);
  const [aiQuestion, setAiQuestion] = useState(null);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiError, setAiError] = useState(null);
  const [questionKey, setQuestionKey] = useState(0);

  const seedBank = category ? SEED_QUESTIONS[category.id] || [] : [];
  const currentFixed = mode === "fixed" && seedBank.length ? seedBank[fixedIdx % seedBank.length] : null;
  const currentQuestion = mode === "ai" ? aiQuestion : currentFixed;

  const loadAi = async () => {
    setAiLoading(true);
    setAiError(null);
    setAiQuestion(null);
    try {
      const q = await fetchAIQuestion(category);
      setAiQuestion(q);
      setQuestionKey((k) => k + 1);
    } catch (err) {
      setAiError(err.message || "Failed to generate question");
    } finally {
      setAiLoading(false);
    }
  };

  const handleAnswered = (correct) => {
    onUpdateStats(category.id, correct);
  };

  const handleNext = () => {
    if (mode === "fixed") {
      setFixedIdx((i) => i + 1);
      setQuestionKey((k) => k + 1);
    } else if (mode === "ai") {
      loadAi();
    }
  };

  const exitToCategory = () => {
    setMode(null);
    setAiQuestion(null);
    setAiError(null);
    setFixedIdx(0);
    setQuestionKey((k) => k + 1);
  };

  const exitToList = () => {
    setCategory(null);
    setMode(null);
    setAiQuestion(null);
    setAiError(null);
    setFixedIdx(0);
  };

  if (!category) return <CategoryGrid stats={stats} onPick={setCategory} />;

  if (!mode) {
    const v = categoryStats(stats, category.id);
    return (
      <div>
        <button style={styles.back} onClick={exitToList}>
          ← back to categories
        </button>
        <div style={styles.questionBox}>
          <div style={styles.cardName}>{category.name}</div>
          <div style={styles.badge}>
            {v.total ? `${v.correct}/${v.total} — ${Math.round((v.correct / v.total) * 100)}%` : "no attempts yet"} ·{" "}
            {seedBank.length} fixed question{seedBank.length === 1 ? "" : "s"} available
          </div>
          <div style={{ marginTop: 18, display: "flex", gap: 10, flexWrap: "wrap" }}>
            <button
              style={seedBank.length ? styles.primary : { ...styles.primary, opacity: 0.4, cursor: "not-allowed" }}
              onClick={() => seedBank.length && setMode("fixed")}
              disabled={!seedBank.length}
            >
              fixed questions
            </button>
            <button
              style={styles.ghost}
              onClick={() => {
                setMode("ai");
                loadAi();
              }}
            >
              AI question
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (mode === "ai" && aiLoading) {
    return (
      <div>
        <button style={styles.back} onClick={exitToCategory}>
          ← back
        </button>
        <div style={styles.questionBox}>
          <div style={styles.loading}>generating question…</div>
        </div>
      </div>
    );
  }

  if (mode === "ai" && aiError) {
    return (
      <div>
        <button style={styles.back} onClick={exitToCategory}>
          ← back
        </button>
        <div style={styles.questionBox}>
          <div style={styles.error}>error: {aiError}</div>
          <div style={{ marginTop: 12, display: "flex", gap: 10 }}>
            <button style={styles.primary} onClick={loadAi}>
              retry
            </button>
            <button style={styles.ghost} onClick={exitToCategory}>
              cancel
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (!currentQuestion) {
    return (
      <div>
        <button style={styles.back} onClick={exitToCategory}>
          ← back
        </button>
        <div style={styles.questionBox}>
          <div style={styles.loading}>no question available</div>
        </div>
      </div>
    );
  }

  return (
    <QuestionView
      key={questionKey}
      q={currentQuestion}
      onAnswered={handleAnswered}
      onNext={handleNext}
      onExit={exitToCategory}
      sourceLabel={
        mode === "fixed"
          ? `${category.name} · fixed ${(fixedIdx % seedBank.length) + 1}/${seedBank.length}`
          : `${category.name} · AI generated`
      }
    />
  );
}

function FrameworkCard({ fw, expanded, onToggle }) {
  return (
    <div style={styles.framework}>
      <button style={styles.fwHeader} onClick={onToggle}>
        <span>{fw.title}</span>
        <span style={{ color: palette.textDim }}>{expanded ? "−" : "+"}</span>
      </button>
      {expanded && (
        <div style={styles.fwBody}>
          {fw.intro.length > 0 && (
            <div style={styles.intro}>
              {fw.intro.map((line, i) => (
                <div key={i}>{line}</div>
              ))}
            </div>
          )}
          <table style={styles.table}>
            <thead>
              <tr>
                {fw.columns.map((c) => (
                  <th key={c} style={styles.th}>
                    {c}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {fw.rows.map((row, i) => (
                <tr key={i}>
                  {row.map((cell, j) => (
                    <td key={j} style={styles.td}>
                      {cell}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
          {fw.rules.length > 0 && (
            <div style={styles.rules}>
              <div style={styles.ruleHead}>critical rules</div>
              {fw.rules.map((r, i) => (
                <div key={i} style={{ marginTop: i === 0 ? 0 : 6 }}>
                  · {r}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function FrameworksMode() {
  const [openId, setOpenId] = useState(null);
  return (
    <div>
      {FRAMEWORKS.map((fw) => (
        <FrameworkCard
          key={fw.id}
          fw={fw}
          expanded={openId === fw.id}
          onToggle={() => setOpenId(openId === fw.id ? null : fw.id)}
        />
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Root component
// ---------------------------------------------------------------------------
export default function App() {
  const [tab, setTab] = useState("drill");
  const [stats, setStats] = useState(emptyStats());
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let cancelled = false;
    loadStats().then((s) => {
      if (!cancelled) {
        setStats(s);
        setLoaded(true);
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const updateCategory = (catId, correct) => {
    setStats((prev) => {
      const cur = prev.perCategory?.[catId] || { correct: 0, total: 0 };
      const next = {
        ...prev,
        perCategory: {
          ...(prev.perCategory || {}),
          [catId]: {
            correct: cur.correct + (correct ? 1 : 0),
            total: cur.total + 1,
          },
        },
        lastSession: new Date().toISOString(),
      };
      saveStats(next);
      return next;
    });
  };

  const reset = () => {
    const fresh = emptyStats();
    setStats(fresh);
    clearStats();
  };

  return (
    <div style={styles.shell}>
      <div style={styles.container}>
        <div style={styles.header}>
          <h1 style={styles.title}>DP-600 // drill</h1>
          <span style={styles.subtitle}>fabric analytics engineer · cram tool</span>
        </div>
        <SummaryBar stats={stats} onReset={reset} />
        <div style={styles.tabs}>
          <button style={styles.tab(tab === "drill")} onClick={() => setTab("drill")}>
            Drill
          </button>
          <button style={styles.tab(tab === "frameworks")} onClick={() => setTab("frameworks")}>
            Frameworks
          </button>
        </div>
        {!loaded ? (
          <div style={styles.loading}>loading…</div>
        ) : tab === "drill" ? (
          <DrillMode stats={stats} onUpdateStats={updateCategory} />
        ) : (
          <FrameworksMode />
        )}
      </div>
    </div>
  );
}
