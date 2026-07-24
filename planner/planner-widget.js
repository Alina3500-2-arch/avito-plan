// Планер на неделю — виджет для Scriptable
// -----------------------------------------------------------------------------
// Как поставить (один раз):
//  1. Установи бесплатное приложение Scriptable из App Store.
//  2. Открой Scriptable → "+" (новый скрипт) → вставь ВЕСЬ этот код.
//  3. Внизу нажми на название скрипта → переименуй в "Планер".
//  4. Запусти скрипт (▶) — откроется меню, добавь пару задач голосом.
//  5. На домашнем экране: долгое нажатие → "+" → найди "Scriptable" →
//     выбери размер виджета → добавь. Затем долгое нажатие по виджету →
//     "Изменить виджет" → Script: "Планер". В поле "Parameter" можно
//     написать "week" (показывать неделю) или оставить пустым (сегодня).
//
// Голос: при добавлении задачи в текстовом поле нажми 🎤 на клавиатуре айфона.
// -----------------------------------------------------------------------------

// ---------- Хранилище ----------
const fm = FileManager.local();
const PATH = fm.joinPath(fm.documentsDirectory(), "planner_tasks.json");

function load() {
  try { if (fm.fileExists(PATH)) return JSON.parse(fm.readString(PATH)); } catch (e) {}
  return [];
}
function save(tasks) { fm.writeString(PATH, JSON.stringify(tasks)); }

// ---------- Даты ----------
const DAYS_SHORT = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];
const MONTHS = ["янв","фев","мар","апр","мая","июн","июл","авг","сен","окт","ноя","дек"];
function pad(n){ return String(n).padStart(2,"0"); }
function dateKey(d){ return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate()); }
function parseKey(k){ const [y,m,dd]=k.split("-").map(Number); return new Date(y,m-1,dd); }
function todayKey(){ return dateKey(new Date()); }
function dow(d){ return (d.getDay()+6)%7; }
function mondayOf(d){ const m=new Date(d); m.setDate(d.getDate()-dow(d)); m.setHours(0,0,0,0); return m; }
function addDaysKey(k, n){ const d=parseKey(k); d.setDate(d.getDate()+n); return dateKey(d); }
function inThisWeek(k){
  const mon=mondayOf(new Date()); const d=parseKey(k);
  const diff=(d-mon)/864e5; return diff>=0 && diff<7;
}
function human(k){ const d=parseKey(k); return DAYS_SHORT[dow(d)]+" "+d.getDate()+" "+MONTHS[d.getMonth()]; }

// ---------- Цвета ----------
const ACCENT = new Color("#8577ff");
const GREEN  = new Color("#22b07d");
const BG1 = new Color("#171722");
const BG2 = new Color("#0f0f16");
const MUTED = new Color("#8a8a9a");
const WHITE = new Color("#f0f0f5");

// ---------- Виджет ----------
function buildWidget(tasks) {
  const param = (args.widgetParameter || "").toLowerCase().trim();
  const showWeek = param === "week" || param === "неделя";
  const family = config.widgetFamily || "medium";

  const w = new ListWidget();
  const g = new LinearGradient();
  g.colors = [BG1, BG2];
  g.locations = [0, 1];
  w.backgroundGradient = g;
  w.setPadding(14, 16, 14, 16);

  // Заголовок
  const head = w.addStack(); head.centerAlignContent();
  const title = head.addText(showWeek ? "📅 Неделя" : "📅 Сегодня");
  title.font = Font.semiboldSystemFont(15); title.textColor = WHITE;
  head.addSpacer();
  const weekLeft = tasks.filter(t => !t.done && inThisWeek(t.date)).length;
  const badge = head.addText(String(weekLeft));
  badge.font = Font.boldSystemFont(15); badge.textColor = ACCENT;
  w.addSpacer(8);

  let items;
  if (showWeek) {
    // Задачи недели по дням
    items = tasks.filter(t => inThisWeek(t.date))
                 .sort((a,b)=> a.date < b.date ? -1 : a.date > b.date ? 1 : 0);
  } else {
    const tk = todayKey();
    items = tasks.filter(t => t.date === tk);
  }

  const max = family === "large" ? 12 : (family === "small" ? 3 : 6);

  if (items.length === 0) {
    const e = w.addText(showWeek ? "На этой неделе задач нет" : "На сегодня задач нет 🎉");
    e.font = Font.systemFont(13); e.textColor = MUTED;
  } else {
    let lastDay = null;
    let shown = 0;
    for (const t of items) {
      if (shown >= max) break;
      if (showWeek && t.date !== lastDay) {
        lastDay = t.date;
        if (shown > 0) w.addSpacer(4);
        const dl = w.addText(human(t.date).toUpperCase());
        dl.font = Font.mediumSystemFont(9); dl.textColor = MUTED;
        w.addSpacer(2);
      }
      const row = w.addStack(); row.centerAlignContent(); row.spacing = 6;
      const mark = row.addText(t.done ? "✓" : "○");
      mark.font = Font.systemFont(12);
      mark.textColor = t.done ? GREEN : ACCENT;
      const tx = row.addText(t.text);
      tx.font = Font.systemFont(13);
      tx.textColor = t.done ? MUTED : WHITE;
      tx.lineLimit = 1;
      shown++;
      w.addSpacer(3);
    }
    const rest = items.length - shown;
    if (rest > 0) {
      const more = w.addText("+ ещё " + rest);
      more.font = Font.systemFont(11); more.textColor = MUTED;
    }
  }

  w.addSpacer();
  const foot = w.addText("Нажми, чтобы добавить →");
  foot.font = Font.systemFont(10); foot.textColor = MUTED;
  return w;
}

// ---------- Меню (когда запускаешь скрипт в приложении) ----------
async function addTaskFlow(tasks) {
  const a = new Alert();
  a.title = "Новая задача";
  a.message = "Напиши или продиктуй (🎤 на клавиатуре)";
  a.addTextField("Что нужно сделать");
  a.addAction("Далее");
  a.addCancelAction("Отмена");
  const r = await a.presentAlert();
  if (r === -1) return;
  const text = a.textFieldValue(0).trim();
  if (!text) return;

  const day = new Alert();
  day.title = "Когда?";
  const opts = ["Сегодня", "Завтра", "Послезавтра"];
  for (let i = 0; i < 3; i++) day.addAction(opts[i] + " · " + human(addDaysKey(todayKey(), i)));
  // Остаток недели
  for (let i = 3; i < 7; i++) day.addAction(human(addDaysKey(todayKey(), i)));
  day.addCancelAction("Отмена");
  const di = await day.presentSheet();
  if (di === -1) return;
  tasks.push({ text, date: addDaysKey(todayKey(), di), done: false, id: Date.now() });
  save(tasks);
}

async function toggleFlow(tasks) {
  const week = tasks.filter(t => inThisWeek(t.date))
                    .sort((a,b)=> a.date < b.date ? -1 : 1);
  if (week.length === 0) { const a=new Alert(); a.title="Задач на неделю нет"; a.addAction("Ок"); await a.presentAlert(); return; }
  const a = new Alert();
  a.title = "Отметить / снять";
  for (const t of week) a.addAction((t.done ? "✓ " : "○ ") + human(t.date) + " — " + t.text);
  a.addCancelAction("Готово");
  const i = await a.presentSheet();
  if (i === -1) return;
  week[i].done = !week[i].done;
  save(tasks);
  await toggleFlow(tasks); // остаться в списке
}

async function menu() {
  let tasks = load();
  const a = new Alert();
  a.title = "Планер";
  const left = tasks.filter(t => !t.done && inThisWeek(t.date)).length;
  a.message = "На этой неделе осталось: " + left;
  a.addAction("➕ Добавить задачу");
  a.addAction("✅ Отметить выполненные");
  a.addAction("👀 Показать виджет");
  a.addCancelAction("Закрыть");
  const r = await a.presentSheet();
  tasks = load();
  if (r === 0) { await addTaskFlow(tasks); await menu(); }
  else if (r === 1) { await toggleFlow(tasks); await menu(); }
  else if (r === 2) {
    const w = buildWidget(load());
    await w.presentMedium();
  }
}

// ---------- Точка входа ----------
if (config.runsInWidget) {
  Script.setWidget(buildWidget(load()));
  Script.complete();
} else if (args.shortcutParameter) {
  // Быстрое добавление через Siri/Быстрые команды: передаётся текст задачи
  const tasks = load();
  const text = String(args.shortcutParameter).trim();
  if (text) { tasks.push({ text, date: todayKey(), done: false, id: Date.now() }); save(tasks); }
  Script.setShortcutOutput("Задача добавлена: " + text);
  Script.complete();
} else {
  await menu();
  const w = buildWidget(load());
  Script.setWidget(w);
  await w.presentMedium();
  Script.complete();
}
