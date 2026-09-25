# =============================================================================
#  Learning Retreat 2026 — Live Audience Results Dashboard
#  "Beyond AI: From Ideas to Impact"  |  Aaron Chen Angus, SSH, Republic Polytechnic
# -----------------------------------------------------------------------------
#  Reads the 5 response tabs of the Google Sheet written by the deck's
#  Apps Script endpoint and refreshes every few seconds.
#
#  Data source (must be shared as "Anyone with the link: Viewer"):
#    https://docs.google.com/spreadsheets/d/1PU45VVHvAU_0ka7CHSVRunT0t1itAuIkz477-yeda4I/edit?usp=sharing
#  Tabs read: BalanceVision, SilverHYROX, CognitiveChallenge, MiloAdventure,
#             MetacognitivePrompt
#
#  Deck:  https://aaron-chen-angus.github.io/learningretreat2026/
#  Repo:  https://github.com/aaron-chen-angus/learningretreat2026
#
#  Run locally:      shiny::runApp("app.R")
#  Rehearse offline: Sys.setenv(LR_DEMO = "1"); shiny::runApp("app.R")
#  Deploy:           rsconnect::deployApp(appFiles = "app.R",
#                                         appName  = "LearningRetreat2026")
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(lubridate)
  library(plotly)
  library(htmltools)
})

# ---- Destination ------------------------------------------------------------
SHEET_ID  <- "1PU45VVHvAU_0ka7CHSVRunT0t1itAuIkz477-yeda4I"
SHEET_URL <- paste0("https://docs.google.com/spreadsheets/d/", SHEET_ID, "/edit?usp=sharing")
DECK_URL  <- "https://aaron-chen-angus.github.io/learningretreat2026/"
REPO_URL  <- "https://github.com/aaron-chen-angus/learningretreat2026"
TZ        <- "Asia/Singapore"
DEMO_MODE <- identical(Sys.getenv("LR_DEMO"), "1")

# ---- Palette (matches the deck) --------------------------------------------
COL <- list(bg = "#02050b", text = "#e8f6ff", muted = "#8fa9c2", dim = "#5b7390",
            blue = "#00e5ff", blue2 = "#0090ff", orange = "#ff7a1a",
            ok = "#3dffb0", bad = "#ff4d6d",
            grid = "rgba(0,229,255,0.12)", line = "rgba(0,229,255,0.22)")

# ---- Sheet schema -----------------------------------------------------------
APP_COLS  <- c("receivedAt", "timestamp", "participantId", "device", "app", "questionId",
               "selected", "selectedText", "correctAnswer", "isCorrect")
META_COLS <- c("receivedAt", "timestamp", "participantId", "device",
               "hospitality", "hospitalityCorrect", "appliedScience", "appliedScienceCorrect",
               "tamd", "tamdCorrect", "business", "businessCorrect", "answered", "score")

# ---- Question metadata (mirrors the deck; answer keys) ----------------------
APPS <- list(
  BalanceVision = list(
    label = "BalanceVision", correct = "A",
    question = "Which gap did the students set out to close?",
    A = "A quick, easy-to-administer fall-risk screen that anyone can run, based on a validated single-leg balance test.",
    B = "A diagnostic device that replaces clinical force-plate balance labs in hospitals.",
    A_short = "Fall-risk screen, validated test", B_short = "Replaces clinical force-plate labs"),
  SilverHYROX = list(
    label = "Silver HYROX", correct = "B",
    question = "Which gap did the students set out to close?",
    A = "A race-timing app that ranks seniors entering competitive HYROX events.",
    B = "A preventive tool that checks seniors do key exercises with proper form, so they build strength and bone health without getting injured.",
    A_short = "Race-timing and ranking app", B_short = "Proper-form preventive tool"),
  CognitiveChallenge = list(
    label = "Cognitive Challenge", correct = "A",
    question = "Which gap did the students set out to close?",
    A = "Online scoring of tasks based on validated cognitive tests, showing how people fare across different domains so early signs can guide preventive health.",
    B = "A brain-training game that raises IQ and diagnoses dementia.",
    A_short = "Validated tests, scored by domain", B_short = "Raises IQ, diagnoses dementia"),
  MiloAdventure = list(
    label = "Milo's Big School Adventure", correct = "B",
    question = "Which gap did the students set out to close?",
    A = "A screening test that diagnoses ADHD in primary school children.",
    B = "A story game that shows how children aged 6 to 9 respond to everyday situations, so parents and preschool coaches know which skills to work on and which to maintain.",
    A_short = "Diagnoses ADHD", B_short = "Adaptability, regulation, problem solving")
)

SCHOOLS <- list(
  hospitality    = list(label = "Hospitality",         correct = "B",
                        ctx = "Guest-feedback dashboard for a hotel front office"),
  appliedScience = list(label = "Applied Science",     correct = "B",
                        ctx = "IgE allergen-analysis dashboard (MALDI-TOF derived epitopes)"),
  tamd           = list(label = "Arts, Media & Design", correct = "B",
                        ctx = "Live sound-engineering dashboard"),
  business       = list(label = "Business",            correct = "A",
                        ctx = "Sales dashboard for an SME owner")
)

# =============================================================================
#  Data access
# =============================================================================
gviz_url <- function(tab) {
  sprintf("https://docs.google.com/spreadsheets/d/%s/gviz/tq?tqx=out:csv&headers=1&sheet=%s&nocache=%s",
          SHEET_ID, utils::URLencode(tab, reserved = TRUE), format(as.numeric(Sys.time()) * 1000, scientific = FALSE))
}

empty_tab <- function(cols) {
  as_tibble(setNames(replicate(length(cols), character(0), simplify = FALSE), cols))
}

read_tab <- function(tab, cols) {
  df <- tryCatch(
    suppressWarnings(readr::read_csv(gviz_url(tab), col_types = cols(.default = col_character()),
                                     na = c("", "NA"), progress = FALSE, show_col_types = FALSE)),
    error = function(e) NULL)
  # A private sheet returns an HTML login page instead of CSV: treat as failure.
  if (is.null(df) || !("participantId" %in% names(df))) return(list(ok = FALSE, data = empty_tab(cols)))
  for (m in setdiff(cols, names(df))) df[[m]] <- NA_character_
  list(ok = TRUE, data = df[, cols, drop = FALSE])
}

# ---- Simulated data for offline rehearsal (LR_DEMO=1) -----------------------
demo_tabs <- function() {
  set.seed(as.integer(Sys.time()) %/% 20)
  now <- Sys.time()
  mk_app <- function(key, n, p_correct) {
    ids <- sprintf("P-%s", toupper(replicate(n, paste(sample(c(letters, 0:9), 6, TRUE), collapse = ""))))
    ok  <- runif(n) < p_correct
    cor <- APPS[[key]]$correct
    sel <- ifelse(ok, cor, setdiff(c("A", "B"), cor))
    t   <- now - sort(runif(n, 0, 1800), decreasing = TRUE)
    tibble(receivedAt = format(t, "%Y-%m-%d %H:%M:%S", tz = TZ),
           timestamp = format(t, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
           participantId = ids, device = sample(c("mobile", "desktop"), n, TRUE, c(.8, .2)),
           app = key, questionId = paste0(key, "_Q1"), selected = sel,
           selectedText = ifelse(sel == "A", APPS[[key]]$A, APPS[[key]]$B),
           correctAnswer = cor, isCorrect = ifelse(ok, "TRUE", "FALSE"))
  }
  res <- list(
    BalanceVision      = list(ok = TRUE, data = mk_app("BalanceVision", 46, .82)),
    SilverHYROX        = list(ok = TRUE, data = mk_app("SilverHYROX", 41, .74)),
    CognitiveChallenge = list(ok = TRUE, data = mk_app("CognitiveChallenge", 38, .69)),
    MiloAdventure      = list(ok = TRUE, data = mk_app("MiloAdventure", 35, .88)))
  n <- 44
  t <- now - sort(runif(n, 0, 900), decreasing = TRUE)
  m <- tibble(receivedAt = format(t, "%Y-%m-%d %H:%M:%S", tz = TZ),
              timestamp = format(t, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
              participantId = sprintf("P-M%04d", 1:n), device = "mobile")
  pc <- c(hospitality = .86, appliedScience = .7, tamd = .9, business = .62)
  for (k in names(SCHOOLS)) {
    ans <- runif(n) < .93
    ok  <- runif(n) < pc[[k]]
    cor <- SCHOOLS[[k]]$correct
    ch  <- ifelse(ok, cor, setdiff(c("A", "B"), cor))
    m[[k]] <- ifelse(ans, ch, "")
    m[[paste0(k, "Correct")]] <- ifelse(ans, ifelse(ok, "TRUE", "FALSE"), "")
  }
  res$MetacognitivePrompt <- list(ok = TRUE, data = mutate(m, answered = NA_character_, score = NA_character_))
  res
}

# =============================================================================
#  Cleaning helpers
# =============================================================================
as_bool <- function(x) {
  x <- toupper(trimws(as.character(x)))
  out <- rep(NA, length(x)); out[x %in% c("TRUE", "1", "YES")] <- TRUE; out[x %in% c("FALSE", "0", "NO")] <- FALSE
  out
}

parse_time <- function(ts, recv) {
  t1 <- with_tz(suppressWarnings(ymd_hms(ts, tz = "UTC", quiet = TRUE)), TZ)
  t2 <- suppressWarnings(parse_date_time(recv, orders = c("Ymd HMS", "mdY HMS", "dmY HMS", "Ymd HM", "mdY HM", "dmY HM"),
                                         tz = TZ, quiet = TRUE))
  if (length(t1) == 0) return(t2)
  t1[is.na(t1)] <- t2[is.na(t1)]
  t1
}

apply_filters <- function(df, excl_test, latest) {
  if (nrow(df) == 0) return(df)
  if (excl_test) df <- df %>% filter(!(participantId %in% "P-TEST"))
  if (latest && nrow(df) > 0) {
    df <- df %>% arrange(participantId, time) %>% group_by(participantId) %>% slice_tail(n = 1) %>% ungroup()
  }
  df %>% arrange(time)
}

prep_app <- function(raw, key, excl_test, latest) {
  cor <- APPS[[key]]$correct
  df <- raw %>%
    mutate(time = parse_time(timestamp, receivedAt),
           selected = toupper(trimws(selected))) %>%
    filter(selected %in% c("A", "B")) %>%
    mutate(isCorrect = coalesce(as_bool(isCorrect), selected == cor))
  apply_filters(df, excl_test, latest)
}

prep_meta <- function(raw, excl_test, latest) {
  df <- raw %>% mutate(time = parse_time(timestamp, receivedAt))
  df <- apply_filters(df, excl_test, latest)
  if (nrow(df) == 0) return(list(sub = df, long = tibble(sid = integer(), participantId = character(),
                                                         time = as.POSIXct(character()), school = character(),
                                                         choice = character(), correct = logical())))
  df$sid <- seq_len(nrow(df))
  long <- bind_rows(lapply(names(SCHOOLS), function(k) {
    tibble(sid = df$sid, participantId = df$participantId, time = df$time, school = k,
           choice = toupper(trimws(df[[k]])), correct_raw = as_bool(df[[paste0(k, "Correct")]]))
  })) %>%
    filter(choice %in% c("A", "B")) %>%
    mutate(correct = coalesce(correct_raw, choice == vapply(school, function(s) SCHOOLS[[s]]$correct, ""))) %>%
    select(-correct_raw)
  sub <- df %>% left_join(long %>% group_by(sid) %>% summarise(n_answered = n(), n_correct = sum(correct), .groups = "drop"),
                          by = "sid") %>%
    mutate(n_answered = coalesce(n_answered, 0L), n_correct = coalesce(n_correct, 0L)) %>%
    filter(n_answered > 0)
  list(sub = sub, long = long %>% filter(sid %in% sub$sid))
}

# =============================================================================
#  Statistics
# =============================================================================
wilson <- function(x, n, conf = 0.95) {
  if (n == 0) return(c(p = NA_real_, lo = NA_real_, hi = NA_real_))
  z <- qnorm(1 - (1 - conf) / 2); p <- x / n
  den <- 1 + z^2 / n
  ctr <- (p + z^2 / (2 * n)) / den
  hw  <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(p = p, lo = max(0, ctr - hw), hi = min(1, ctr + hw))
}

binom_p <- function(x, n) if (n > 0) binom.test(x, n, p = 0.5, alternative = "two.sided")$p.value else NA_real_

cochran_q <- function(mat) {
  mat <- as.matrix(mat) * 1
  k <- ncol(mat); N <- nrow(mat)
  if (N < 2) return(list(Q = NA_real_, df = k - 1, p = NA_real_, N = N))
  C <- colSums(mat); R <- rowSums(mat); Tt <- sum(mat)
  den <- k * Tt - sum(R^2)
  if (den == 0) return(list(Q = NA_real_, df = k - 1, p = NA_real_, N = N))
  Q <- (k - 1) * (k * sum(C^2) - Tt^2) / den
  list(Q = Q, df = k - 1, p = pchisq(Q, k - 1, lower.tail = FALSE), N = N)
}

fmt_pct <- function(x, d = 0) ifelse(is.na(x), "–", sprintf(paste0("%.", d, "f%%"), 100 * x))
fmt_p   <- function(p) ifelse(is.na(p), "–", ifelse(p < 0.001, "< .001", sub("^0", "", sprintf("%.3f", p))))
p_str   <- function(p) ifelse(is.na(p), "–", ifelse(p < 0.001, "p < .001", paste0("p = ", fmt_p(p))))

# =============================================================================
#  Plot helpers
# =============================================================================
tron <- function(p, xaxis = list(), yaxis = list(), margin = NULL, legend = list(), ...) {
  ax <- list(gridcolor = COL$grid, zerolinecolor = COL$line, linecolor = COL$line,
             tickfont = list(color = COL$muted), titlefont = list(color = COL$muted, size = 12), automargin = TRUE)
  p %>% layout(
    paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
    font = list(family = "'Exo 2', 'Segoe UI', sans-serif", color = COL$text, size = 13),
    xaxis = modifyList(ax, xaxis), yaxis = modifyList(ax, yaxis),
    hoverlabel = list(bgcolor = "#06121f", bordercolor = COL$blue, font = list(color = COL$text, family = "Exo 2")),
    legend = modifyList(list(font = list(color = COL$muted), orientation = "h", x = 0, y = -0.28), legend),
    margin = if (is.null(margin)) list(l = 10, r = 20, t = 20, b = 40) else margin, ...) %>%
    config(displayModeBar = FALSE, responsive = TRUE)
}

empty_plot <- function(msg = "Waiting for votes\u2026") {
  plot_ly(type = "scatter", mode = "markers", x = numeric(0), y = numeric(0), hoverinfo = "none") %>%
    tron(xaxis = list(visible = FALSE), yaxis = list(visible = FALSE),
         annotations = list(list(text = msg, x = 0.5, y = 0.5, xref = "paper", yref = "paper", showarrow = FALSE,
                                 font = list(family = "Orbitron", size = 16, color = COL$dim))))
}

chance_line <- function(axis = "y") {
  if (axis == "y") list(type = "line", xref = "paper", x0 = 0, x1 = 1, y0 = 0.5, y1 = 0.5,
                        line = list(color = COL$orange, dash = "dash", width = 1.5))
  else list(type = "line", yref = "paper", y0 = 0, y1 = 1, x0 = 0.5, x1 = 0.5,
            line = list(color = COL$orange, dash = "dash", width = 1.5))
}

kpi <- function(label, value, sub = NULL, accent = "blue") {
  div(class = paste("kpi", accent),
      div(class = "kpi-label", label), div(class = "kpi-value", value),
      if (!is.null(sub)) div(class = "kpi-sub", HTML(sub)))
}

# =============================================================================
#  Theme and CSS
# =============================================================================
theme <- bs_theme(
  version = 5, bg = COL$bg, fg = COL$text, primary = COL$blue, secondary = COL$orange,
  success = COL$ok, danger = COL$bad,
  base_font = font_google("Exo 2", local = FALSE),
  heading_font = font_google("Orbitron", local = FALSE),
  "border-radius" = "12px", "card-bg" = "rgba(5,14,28,0.82)", "card-border-color" = COL$line
)

css <- HTML(sprintf("
body{background:%1$s; min-height:100vh; font-family:'Exo 2','Segoe UI',system-ui,sans-serif;}
body::before{content:''; position:fixed; left:-50%%; right:-50%%; top:55%%; height:120%%; z-index:-1; pointer-events:none;
  background-image:linear-gradient(rgba(0,229,255,.22) 1px,transparent 1px),linear-gradient(90deg,rgba(0,229,255,.22) 1px,transparent 1px);
  background-size:60px 60px; transform:perspective(420px) rotateX(62deg); transform-origin:top center;
  -webkit-mask-image:linear-gradient(to bottom,rgba(0,0,0,.8),transparent 70%%); mask-image:linear-gradient(to bottom,rgba(0,0,0,.8),transparent 70%%);}
body::after{content:''; position:fixed; inset:0; z-index:-2; pointer-events:none;
  background:radial-gradient(ellipse at 50%% 55%%,rgba(0,144,255,.16),transparent 55%%),radial-gradient(circle at 88%% 8%%,rgba(255,122,26,.10),transparent 40%%);}
.container-fluid{max-width:1480px; padding:18px clamp(12px,3vw,36px) 40px;}
h1,h2,h3,h4,.nav-link,.kpi-value,.kicker{font-family:'Orbitron','Segoe UI',sans-serif;}
.top{display:flex; flex-wrap:wrap; gap:16px; align-items:flex-end; justify-content:space-between; margin-bottom:14px;}
.top .kicker{color:%3$s; font-size:12px; letter-spacing:.14em;}
.top h1{font-size:clamp(20px,2.6vw,34px); margin:4px 0 0; text-shadow:0 0 18px rgba(0,229,255,.4);}
.top h1 span{color:%3$s; text-shadow:0 0 18px rgba(255,122,26,.5);}
.links a{color:%2$s; font-size:13px; margin-right:14px; text-decoration:none; border-bottom:1px solid rgba(0,229,255,.35);}
.controls{display:flex; flex-wrap:wrap; gap:14px 22px; align-items:center; padding:12px 16px; margin-bottom:16px;
  background:rgba(5,14,28,.82); border:1px solid %5$s; border-radius:12px;}
.controls .form-group{margin:0;} .controls label{color:%4$s; font-size:13px;}
.controls .form-select{background-color:#06121f; color:#e8f6ff; border-color:%5$s; min-width:110px;}
.controls .form-check-input:checked{background-color:%2$s; border-color:%2$s;}
.status{margin-left:auto; display:flex; align-items:center; gap:10px; font-size:13px; color:%4$s;}
.dot{width:10px; height:10px; border-radius:50%%; background:#3dffb0; box-shadow:0 0 10px #3dffb0; animation:pulse 1.6s infinite;}
.dot.off{background:#ff4d6d; box-shadow:0 0 10px #ff4d6d;} .dot.demo{background:%3$s; box-shadow:0 0 10px %3$s;}
@keyframes pulse{0%%,100%%{opacity:1} 50%%{opacity:.35}}
@media (prefers-reduced-motion:reduce){.dot{animation:none;}}
.btn-refresh{border:1px solid rgba(0,229,255,.45); background:rgba(0,229,255,.06); color:#e8f6ff; font-weight:600;}
.btn-refresh:hover{box-shadow:0 0 14px rgba(0,229,255,.4); color:#fff;}
.nav-tabs{border-bottom:1px solid %5$s; gap:4px; flex-wrap:wrap;}
.nav-tabs .nav-link{color:%4$s; font-size:12.5px; letter-spacing:.04em; border:1px solid transparent; border-radius:10px 10px 0 0;}
.nav-tabs .nav-link.active{color:%2$s; background:rgba(0,229,255,.08); border-color:%5$s %5$s transparent; text-shadow:0 0 10px rgba(0,229,255,.6);}
.tab-content{padding-top:18px;}
.kpis{display:grid; grid-template-columns:repeat(4,1fr); gap:14px; margin-bottom:16px;}
@media (max-width:900px){.kpis{grid-template-columns:repeat(2,1fr);}}
.kpi{padding:16px 18px; border-radius:12px; background:rgba(5,14,28,.82); border:1px solid %5$s;}
.kpi.blue{border-color:rgba(0,229,255,.5); box-shadow:0 0 18px rgba(0,229,255,.12);}
.kpi.orange{border-color:rgba(255,122,26,.55); box-shadow:0 0 18px rgba(255,122,26,.14);}
.kpi.green{border-color:rgba(61,255,176,.5); box-shadow:0 0 18px rgba(61,255,176,.12);}
.kpi-label{font-size:12.5px; color:%4$s;}
.kpi-value{font-size:clamp(22px,2.4vw,32px); font-weight:700; margin-top:4px;}
.kpi.blue .kpi-value{color:%2$s; text-shadow:0 0 14px rgba(0,229,255,.55);}
.kpi.orange .kpi-value{color:%3$s; text-shadow:0 0 14px rgba(255,122,26,.55);}
.kpi.green .kpi-value{color:#3dffb0; text-shadow:0 0 14px rgba(61,255,176,.5);}
.kpi-sub{font-size:12.5px; color:%4$s; margin-top:4px;}
.card{backdrop-filter:blur(6px); margin-bottom:16px;}
.card-header{background:transparent; border-bottom:1px solid %5$s; font-family:'Orbitron',sans-serif; font-size:13px; color:%2$s; letter-spacing:.04em;}
.qhead{margin-bottom:14px;} .qhead .kicker{color:%3$s; font-size:12px; letter-spacing:.14em;}
.qhead h2{font-size:clamp(18px,2vw,26px); margin-top:4px;}
.opt{display:flex; gap:12px; padding:10px 12px; border:1px solid %5$s; border-radius:10px; margin-bottom:10px; font-size:14px;}
.opt .key{flex:none; width:26px; height:26px; border-radius:7px; display:grid; place-items:center; font-family:Orbitron; font-size:12px; border:1px solid rgba(0,229,255,.45); color:%2$s;}
.opt.correct{border-color:rgba(61,255,176,.6); box-shadow:0 0 12px rgba(61,255,176,.18);}
.opt.correct .key{background:#3dffb0; color:#002214; border-color:#3dffb0;}
.interp{font-size:14.5px; line-height:1.6; margin-top:6px;}
.interp b{color:%2$s;}
.muted{color:%4$s; font-size:13px;}
table.recent{width:100%%; font-size:13.5px;}
table.recent th{color:%4$s; font-weight:500; padding:6px 4px; border-bottom:1px solid %5$s;}
table.recent td{padding:6px 4px; border-bottom:1px solid rgba(0,229,255,.08);}
.yes{color:#3dffb0;} .no{color:#ff4d6d;}
.foot{margin-top:18px; font-size:12.5px; color:#5b7390;}
", COL$bg, COL$blue, COL$orange, COL$muted, COL$line))

# =============================================================================
#  UI
# =============================================================================
app_panel <- function(key) {
  m <- APPS[[key]]
  nav_panel(
    title = m$label, value = key,
    div(class = "qhead", div(class = "kicker", toupper(m$label)), h2(m$question)),
    uiOutput(paste0(key, "_kpis")),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("How the room voted"), plotlyOutput(paste0(key, "_bar"), height = "300px")),
      card(card_header("Cumulative accuracy with 95% Wilson CI"), plotlyOutput(paste0(key, "_trend"), height = "300px"))
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(card_header("Options and interpretation"), uiOutput(paste0(key, "_interp"))),
      card(card_header("Latest responses"), uiOutput(paste0(key, "_recent")))
    )
  )
}

ui <- page_fluid(
  theme = theme,
  tags$head(tags$title("Learning Retreat 2026 | Live Results"), tags$style(css)),
  div(class = "top",
      div(div(class = "kicker", "LEARNING RETREAT 2026 \u00b7 SCHOOL SHARING SESSION"),
          h1("Live results: ", tags$span("Beyond AI"))),
      div(class = "links",
          tags$a(href = DECK_URL, target = "_blank", "Open the deck"),
          tags$a(href = SHEET_URL, target = "_blank", "Google Sheet"),
          tags$a(href = REPO_URL, target = "_blank", "Repo"))),
  div(class = "controls",
      selectInput("interval", "Refresh every", c("5 s" = 5, "10 s" = 10, "15 s" = 15, "30 s" = 30, "60 s" = 60),
                  selected = 10, width = "130px"),
      checkboxInput("latest", "One vote per participant (latest)", TRUE),
      checkboxInput("excl_test", "Exclude test rows (P-TEST)", TRUE),
      actionButton("refresh", "Refresh now", class = "btn-refresh btn-sm"),
      uiOutput("status", inline = TRUE)),
  navset_tab(
    id = "tabs",
    nav_panel(
      title = "Overview", value = "overview",
      uiOutput("ov_kpis"),
      layout_columns(
        col_widths = c(7, 5),
        card(card_header("Proportion correct by question, 95% Wilson CI (dashed line = 50% chance)"),
             plotlyOutput("ov_acc", height = "380px")),
        card(card_header("Submissions over time"), plotlyOutput("ov_time", height = "380px"))
      )
    ),
    app_panel("BalanceVision"),
    app_panel("SilverHYROX"),
    app_panel("CognitiveChallenge"),
    app_panel("MiloAdventure"),
    nav_panel(
      title = "Metacognitive Prompt", value = "MetacognitivePrompt",
      div(class = "qhead", div(class = "kicker", "SPOT THE METACOGNITIVE PROMPT"),
          h2("Which prompt makes the student think?")),
      uiOutput("mc_kpis"),
      layout_columns(
        col_widths = c(6, 6),
        card(card_header("Proportion correct by school, 95% Wilson CI"), plotlyOutput("mc_acc", height = "320px")),
        card(card_header("Choices by school"), plotlyOutput("mc_choice", height = "320px"))
      ),
      layout_columns(
        col_widths = c(5, 7),
        card(card_header("Score distribution (complete submissions, out of 4)"), plotlyOutput("mc_score", height = "300px")),
        card(card_header("Statistical summary"), uiOutput("mc_stats"))
      )
    )
  ),
  div(class = "foot",
      "Pseudonymous participant IDs only. Proportions use Wilson score intervals; the exact binomial test compares ",
      "against 50% (two options). Difficulty across schools is tested with Cochran's Q on complete submissions.")
)

# =============================================================================
#  Server
# =============================================================================
server <- function(input, output, session) {

  tabs_raw <- reactive({
    input$refresh
    invalidateLater(as.numeric(input$interval) * 1000)
    if (DEMO_MODE) return(list(res = demo_tabs(), fetched = Sys.time()))
    res <- list(
      BalanceVision       = read_tab("BalanceVision", APP_COLS),
      SilverHYROX         = read_tab("SilverHYROX", APP_COLS),
      CognitiveChallenge  = read_tab("CognitiveChallenge", APP_COLS),
      MiloAdventure       = read_tab("MiloAdventure", APP_COLS),
      MetacognitivePrompt = read_tab("MetacognitivePrompt", META_COLS))
    list(res = res, fetched = Sys.time())
  })

  app_data <- lapply(setNames(names(APPS), names(APPS)), function(key) {
    reactive(prep_app(tabs_raw()$res[[key]]$data, key, input$excl_test, input$latest))
  })
  meta_data <- reactive(prep_meta(tabs_raw()$res$MetacognitivePrompt$data, input$excl_test, input$latest))

  output$status <- renderUI({
    r <- tabs_raw()
    n_ok <- sum(vapply(r$res, `[[`, logical(1), "ok"))
    cls <- if (DEMO_MODE) "dot demo" else if (n_ok == 5) "dot" else "dot off"
    msg <- if (DEMO_MODE) "Demo data (LR_DEMO=1)" else if (n_ok == 5) "Live: 5 of 5 tabs" else
      sprintf("%d of 5 tabs reachable. Is the sheet shared as Anyone with the link?", n_ok)
    div(class = "status", span(class = cls), span(msg),
        span(paste("Updated", format(r$fetched, "%H:%M:%S", tz = TZ), "SGT")))
  })

  # ---- Per-app outputs --------------------------------------------------------
  for (key in names(APPS)) local({
    k <- key; m <- APPS[[k]]; d <- app_data[[k]]

    output[[paste0(k, "_kpis")]] <- renderUI({
      df <- d(); n <- nrow(df); x <- sum(df$isCorrect)
      w <- wilson(x, n); p <- binom_p(x, n)
      div(class = "kpis",
          kpi("Responses", n, sprintf("%d mobile \u00b7 %d desktop", sum(df$device %in% "mobile"), sum(df$device %in% "desktop"))),
          kpi("Chose the correct basis", fmt_pct(w["p"]),
              if (n > 0) sprintf("95%% CI %s to %s", fmt_pct(w["lo"]), fmt_pct(w["hi"])) else NULL, "green"),
          kpi("Exact binomial vs 50%", if (n > 0) p_str(p) else "–",
              if (n > 0) (if (p < 0.05) "Different from chance" else "Not distinguishable from chance") else NULL, "orange"),
          kpi("Correct answer", m$correct, if (m$correct == "A") m$A_short else m$B_short))
    })

    output[[paste0(k, "_bar")]] <- renderPlotly({
      df <- d(); if (nrow(df) == 0) return(empty_plot())
      cnt <- df %>% count(selected) %>% right_join(tibble(selected = c("A", "B")), by = "selected") %>%
        mutate(n = coalesce(n, 0L), pct = n / sum(n),
               lab = paste0(selected, " \u00b7 ", ifelse(selected == "A", m$A_short, m$B_short)),
               col = ifelse(selected == m$correct, COL$ok, COL$orange))
      cnt$lab <- factor(cnt$lab, levels = rev(cnt$lab))
      plot_ly(cnt, y = ~lab, x = ~n, type = "bar", orientation = "h",
              marker = list(color = ~col, line = list(color = ~col, width = 2), opacity = 0.85),
              text = ~sprintf("%d (%s)", n, fmt_pct(pct)), textposition = "outside",
              textfont = list(color = COL$text, family = "Orbitron"),
              hovertemplate = "%{y}<br>%{x} votes<extra></extra>") %>%
        tron(xaxis = list(title = "Votes", rangemode = "tozero"), yaxis = list(title = ""),
             margin = list(l = 10, r = 60, t = 10, b = 40), bargap = 0.35)
    })

    output[[paste0(k, "_trend")]] <- renderPlotly({
      df <- d(); if (nrow(df) == 0) return(empty_plot())
      df <- df %>% mutate(i = row_number(), cx = cumsum(isCorrect))
      ci <- t(mapply(function(x, n) wilson(x, n), df$cx, df$i))
      df$p <- ci[, "p"]; df$lo <- ci[, "lo"]; df$hi <- ci[, "hi"]
      xvar <- if (all(!is.na(df$time))) df$time else df$i
      plot_ly(x = xvar) %>%
        add_ribbons(ymin = df$lo, ymax = df$hi, fillcolor = "rgba(0,229,255,0.14)",
                    line = list(color = "rgba(0,0,0,0)"), hoverinfo = "none", name = "95% CI") %>%
        add_lines(y = df$p, line = list(color = COL$blue, width = 3, shape = "hv"), name = "Cumulative % correct",
                  text = sprintf("n = %d<br>%s correct<br>CI %s to %s", df$i, fmt_pct(df$p), fmt_pct(df$lo), fmt_pct(df$hi)),
                  hovertemplate = "%{text}<extra></extra>") %>%
        tron(yaxis = list(title = "", range = c(0, 1.02), tickformat = ".0%"),
             xaxis = list(title = if (inherits(xvar, "POSIXct")) "Time (SGT)" else "Response #"),
             shapes = list(chance_line("y")), showlegend = FALSE)
    })

    output[[paste0(k, "_interp")]] <- renderUI({
      df <- d(); n <- nrow(df); x <- sum(df$isCorrect); w <- wilson(x, n); p <- binom_p(x, n)
      opt <- function(letter, txt) div(class = paste("opt", if (letter == m$correct) "correct" else ""),
                                       span(class = "key", letter), span(txt))
      verdict <- if (n == 0) "No votes yet." else if (n < 10)
        sprintf("<b>%d of %d</b> (%s) chose the correct basis so far. With fewer than 10 votes the interval is wide, so read it as a trend only.",
                x, n, fmt_pct(w["p"]))
      else sprintf("<b>%d of %d</b> participants (%s, 95%% CI %s to %s) identified the students' intended gap. The exact binomial test against 50%% chance gives %s, so the room's choice is %s.",
                   x, n, fmt_pct(w["p"]), fmt_pct(w["lo"]), fmt_pct(w["hi"]), p_str(p),
                   if (p < 0.05) (if (w["p"] > 0.5) "reliably above chance" else "reliably below chance: the distractor was more persuasive")
                   else "not yet distinguishable from guessing")
      tagList(opt("A", m$A), opt("B", m$B), div(class = "interp", HTML(verdict)))
    })

    output[[paste0(k, "_recent")]] <- renderUI({
      df <- d(); if (nrow(df) == 0) return(div(class = "muted", "No responses yet."))
      last <- df %>% arrange(desc(time)) %>% head(8)
      tags$table(class = "recent",
                 tags$thead(tags$tr(tags$th("Time"), tags$th("Participant"), tags$th("Vote"), tags$th(""))),
                 tags$tbody(lapply(seq_len(nrow(last)), function(i) tags$tr(
                   tags$td(ifelse(is.na(last$time[i]), "–", format(last$time[i], "%H:%M:%S", tz = TZ))),
                   tags$td(last$participantId[i]), tags$td(last$selected[i]),
                   tags$td(if (isTRUE(last$isCorrect[i])) span(class = "yes", "\u2713") else span(class = "no", "\u2717"))))))
    })
  })

  # ---- Metacognitive prompt -----------------------------------------------------
  output$mc_kpis <- renderUI({
    md <- meta_data(); sub <- md$sub; long <- md$long
    comp <- sub %>% filter(n_answered == 4)
    ms <- if (nrow(comp) > 0) mean(comp$n_correct) else NA
    ci <- if (nrow(comp) >= 2) { se <- sd(comp$n_correct) / sqrt(nrow(comp)); ms + c(-1, 1) * qt(.975, nrow(comp) - 1) * se } else c(NA, NA)
    w <- wilson(sum(long$correct), nrow(long))
    div(class = "kpis",
        kpi("Submissions", nrow(sub), sprintf("%d answered all 4", nrow(comp))),
        kpi("Mean score (complete)", if (is.na(ms)) "–" else sprintf("%.2f / 4", ms),
            if (!is.na(ci[1])) sprintf("95%% CI %.2f to %.2f", max(0, ci[1]), min(4, ci[2])) else NULL, "green"),
        kpi("Answers correct overall", fmt_pct(w["p"]),
            if (nrow(long) > 0) sprintf("%d of %d answers", sum(long$correct), nrow(long)) else NULL),
        kpi("Perfect 4 / 4", if (nrow(comp) > 0) fmt_pct(mean(comp$n_correct == 4)) else "–",
            if (nrow(comp) > 0) sprintf("%d participants", sum(comp$n_correct == 4)) else NULL, "orange"))
  })

  school_summary <- reactive({
    long <- meta_data()$long
    bind_rows(lapply(names(SCHOOLS), function(s) {
      x <- long %>% filter(school == s); w <- wilson(sum(x$correct), nrow(x))
      tibble(school = s, label = SCHOOLS[[s]]$label, n = nrow(x), k = sum(x$correct),
             p = w["p"], lo = w["lo"], hi = w["hi"], pval = binom_p(sum(x$correct), nrow(x)))
    }))
  })

  output$mc_acc <- renderPlotly({
    s <- school_summary(); if (sum(s$n) == 0) return(empty_plot())
    s$label <- factor(s$label, levels = s$label)
    plot_ly(s, x = ~label, y = ~p, type = "bar",
            marker = list(color = "rgba(0,229,255,0.55)", line = list(color = COL$blue, width = 2)),
            error_y = list(type = "data", symmetric = FALSE, array = ~hi - p, arrayminus = ~p - lo,
                           color = COL$text, thickness = 1.5, width = 6),
            text = ~sprintf("%s<br>n = %d", fmt_pct(p), n), textposition = "none",
            hovertemplate = "%{x}<br>%{text}<extra></extra>") %>%
      tron(yaxis = list(title = "", range = c(0, 1.05), tickformat = ".0%"), xaxis = list(title = ""),
           shapes = list(chance_line("y")), bargap = 0.4)
  })

  output$mc_choice <- renderPlotly({
    long <- meta_data()$long; if (nrow(long) == 0) return(empty_plot())
    tab <- long %>% count(school, choice) %>%
      complete(school = names(SCHOOLS), choice = c("A", "B"), fill = list(n = 0)) %>%
      mutate(label = factor(vapply(school, function(s) SCHOOLS[[s]]$label, ""), levels = vapply(SCHOOLS, `[[`, "", "label")),
             is_cor = choice == vapply(school, function(s) SCHOOLS[[s]]$correct, ""),
             grp = ifelse(is_cor, "Metacognitive prompt (correct)", "Direct prompt"))
    plot_ly(tab, x = ~label, y = ~n, color = ~grp, type = "bar",
            colors = setNames(c(COL$ok, COL$orange), c("Metacognitive prompt (correct)", "Direct prompt")),
            text = ~paste0("Option ", choice), hovertemplate = "%{x}<br>%{text}: %{y} votes<extra></extra>") %>%
      tron(barmode = "stack", yaxis = list(title = "Votes"), xaxis = list(title = ""), bargap = 0.4)
  })

  output$mc_score <- renderPlotly({
    comp <- meta_data()$sub %>% filter(n_answered == 4); if (nrow(comp) == 0) return(empty_plot("Waiting for complete submissions\u2026"))
    d <- tibble(score = 0:4) %>% left_join(comp %>% count(score = n_correct), by = "score") %>% mutate(n = coalesce(n, 0L))
    plot_ly(d, x = ~factor(score), y = ~n, type = "bar",
            marker = list(color = ifelse(d$score == 4, COL$ok, "rgba(0,229,255,0.55)"),
                          line = list(color = ifelse(d$score == 4, COL$ok, COL$blue), width = 2)),
            hovertemplate = "Score %{x} / 4<br>%{y} participants<extra></extra>") %>%
      tron(xaxis = list(title = "Score"), yaxis = list(title = "Participants"), bargap = 0.3)
  })

  output$mc_stats <- renderUI({
    md <- meta_data(); s <- school_summary()
    comp_ids <- md$sub %>% filter(n_answered == 4) %>% pull(sid)
    mat <- md$long %>% filter(sid %in% comp_ids) %>% select(sid, school, correct) %>%
      pivot_wider(names_from = school, values_from = correct)
    q <- if (nrow(mat) > 0) cochran_q(mat[, names(SCHOOLS)]) else list(Q = NA, df = 3, p = NA, N = 0)
    rows <- lapply(seq_len(nrow(s)), function(i) tags$tr(
      tags$td(s$label[i]), tags$td(s$n[i]), tags$td(fmt_pct(s$p[i])),
      tags$td(if (s$n[i] > 0) sprintf("%s to %s", fmt_pct(s$lo[i]), fmt_pct(s$hi[i])) else "–"),
      tags$td(fmt_p(s$pval[i]))))
    q_txt <- if (is.na(q$Q)) {
      if (q$N < 2) "Cochran's Q needs at least 2 complete submissions."
      else "Cochran's Q is undefined because every complete submission scored identically across schools."
    } else sprintf("Cochran's Q(%d) = %.2f, %s, N = %d complete submissions. %s",
                   q$df, q$Q, p_str(q$p), q$N,
                   if (q$p < 0.05) "Accuracy differs across the four school scenarios, so some prompts were harder to judge than others."
                   else "No evidence that the four school scenarios differed in difficulty.")
    tagList(
      tags$table(class = "recent",
                 tags$thead(tags$tr(tags$th("School"), tags$th("n"), tags$th("% correct"),
                                    tags$th("95% Wilson CI"), tags$th("Binomial p vs 50%"))),
                 tags$tbody(rows)),
      div(class = "interp", style = "margin-top:12px", q_txt))
  })

  # ---- Overview ---------------------------------------------------------------------
  output$ov_kpis <- renderUI({
    apps <- lapply(app_data, function(f) f())
    md <- meta_data()
    n_total <- sum(vapply(apps, nrow, 0L)) + nrow(md$sub)
    ids <- unique(c(unlist(lapply(apps, `[[`, "participantId")), md$sub$participantId))
    all_app <- bind_rows(apps)
    w <- wilson(sum(all_app$isCorrect), nrow(all_app))
    wm <- wilson(sum(md$long$correct), nrow(md$long))
    last <- suppressWarnings(max(c(all_app$time, md$sub$time), na.rm = TRUE))
    div(class = "kpis",
        kpi("Total submissions", n_total, "Across all 5 activities"),
        kpi("Unique participants", length(na.omit(ids)), "Pseudonymous device IDs", "orange"),
        kpi("App questions correct", fmt_pct(w["p"]),
            if (nrow(all_app) > 0) sprintf("95%% CI %s to %s", fmt_pct(w["lo"]), fmt_pct(w["hi"])) else NULL, "green"),
        kpi("Prompt answers correct", fmt_pct(wm["p"]),
            if (is.finite(last)) paste("Last vote", format(last, "%H:%M:%S", tz = TZ)) else "No votes yet"))
  })

  output$ov_acc <- renderPlotly({
    apps <- lapply(app_data, function(f) f())
    a <- bind_rows(lapply(names(APPS), function(k) {
      df <- apps[[k]]; w <- wilson(sum(df$isCorrect), nrow(df))
      tibble(label = APPS[[k]]$label, grp = "App brief", n = nrow(df), p = w["p"], lo = w["lo"], hi = w["hi"])
    }))
    s <- school_summary() %>% transmute(label = paste0("Prompt: ", label), grp = "Metacognitive prompt", n, p, lo, hi)
    d <- bind_rows(a, s)
    if (sum(d$n) == 0) return(empty_plot())
    d$label <- factor(d$label, levels = rev(d$label))
    plot_ly(d, y = ~label, x = ~p, color = ~grp, type = "scatter", mode = "markers",
            colors = setNames(c(COL$blue, COL$orange), c("App brief", "Metacognitive prompt")),
            marker = list(size = 13, line = list(color = COL$text, width = 1)),
            error_x = list(type = "data", symmetric = FALSE, array = ~hi - p, arrayminus = ~p - lo, thickness = 2, width = 5),
            text = ~sprintf("%s<br>%s correct (n = %d)", label, fmt_pct(p), n),
            hovertemplate = "%{text}<extra></extra>") %>%
      tron(xaxis = list(title = "", range = c(0, 1.02), tickformat = ".0%"), yaxis = list(title = ""),
           shapes = list(chance_line("x")), margin = list(l = 10, r = 20, t = 10, b = 60))
  })

  output$ov_time <- renderPlotly({
    apps <- lapply(app_data, function(f) f()); md <- meta_data()
    ser <- c(lapply(names(APPS), function(k) tibble(tab = APPS[[k]]$label, time = apps[[k]]$time)),
             list(tibble(tab = "Metacognitive prompt", time = md$sub$time)))
    d <- bind_rows(ser) %>% filter(!is.na(time)) %>% arrange(tab, time) %>% group_by(tab) %>% mutate(cum = row_number()) %>% ungroup()
    if (nrow(d) == 0) return(empty_plot())
    pal <- setNames(c(COL$blue, COL$orange, "#7fb2ff", "#ffb070", COL$ok),
                    c(vapply(APPS, `[[`, "", "label"), "Metacognitive prompt"))
    plot_ly(d, x = ~time, y = ~cum, color = ~tab, colors = pal, type = "scatter", mode = "lines",
            line = list(width = 2.5, shape = "hv"),
            hovertemplate = "%{fullData.name}<br>%{y} submissions<extra></extra>") %>%
      tron(xaxis = list(title = "Time (SGT)"), yaxis = list(title = "Cumulative submissions", rangemode = "tozero"))
  })
}

shinyApp(ui, server)
