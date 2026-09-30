'use strict';

const STORE_KEY = 'salliha.jobs.v1';
const $ = (id) => document.getElementById(id);
const fields = ['customer', 'phone', 'device', 'serial', 'issue', 'price', 'paid', 'status', 'notes'];
const statusClass = {
  'تم الاستلام': 's-new', 'قيد الفحص': 's-check', 'انتظار الموافقة': 's-wait', 'انتظار قطعة': 's-wait',
  'قيد التصليح': 's-work', 'جاهز': 's-ready', 'تم التسليم': 's-done'
};

let jobs = load();

function load() {
  try { return JSON.parse(localStorage.getItem(STORE_KEY)) || []; } catch { return []; }
}
function save() {
  try { localStorage.setItem(STORE_KEY, JSON.stringify(jobs)); } catch { alert('تعذّر حفظ البيانات على هذا الجهاز'); }
}

// Accept Arabic-Indic digits and Arabic decimal separators.
function toNumber(v) {
  const s = String(v ?? '').replace(/[٠-٩]/g, (d) => '٠١٢٣٤٥٦٧٨٩'.indexOf(d))
    .replace(/[۰-۹]/g, (d) => '۰۱۲۳۴۵۶۷۸۹'.indexOf(d)).replace(/[٫,]/g, '.').replace(/[^\d.]/g, '');
  const n = parseFloat(s);
  return Number.isFinite(n) ? n : 0;
}
const money = (n) => n.toLocaleString('ar', { maximumFractionDigits: 2 });
const due = (j) => Math.max(0, j.price - j.paid);
const isToday = (ts) => new Date(ts).toDateString() === new Date().toDateString();

function nextNumber() {
  return jobs.reduce((m, j) => Math.max(m, j.number || 0), 1000) + 1;
}

function render() {
  const q = $('searchInput').value.trim().toLowerCase();
  const f = $('statusFilter').value;
  const list = jobs
    .filter((j) => !f || j.status === f)
    .filter((j) => !q || [j.customer, j.phone, j.device, j.serial, String(j.number)].some((v) => (v || '').toLowerCase().includes(q)))
    .sort((a, b) => b.created - a.created);

  const tpl = $('jobTemplate');
  const box = $('jobs');
  box.replaceChildren();
  for (const j of list) {
    const el = tpl.content.firstElementChild.cloneNode(true);
    el.dataset.id = j.id;
    el.querySelector('.job-number').textContent = '#' + j.number;
    el.querySelector('.job-device').textContent = j.device;
    el.querySelector('.job-customer').textContent = `${j.customer} · ${j.phone}`;
    const pill = el.querySelector('.status-pill');
    pill.textContent = j.status;
    pill.classList.add(statusClass[j.status] || 's-new');
    el.querySelector('.job-issue').textContent = j.issue;
    el.querySelector('.job-price').textContent = money(j.price);
    el.querySelector('.job-due').textContent = money(due(j));
    box.append(el);
  }
  $('empty').hidden = jobs.length > 0;
  if (jobs.length && !list.length) box.innerHTML = '<p class="no-results">لا توجد نتائج مطابقة</p>';

  $('todayCount').textContent = jobs.filter((j) => isToday(j.created)).length;
  $('activeCount').textContent = jobs.filter((j) => !['جاهز', 'تم التسليم'].includes(j.status)).length;
  $('readyCount').textContent = jobs.filter((j) => j.status === 'جاهز').length;
  $('dueTotal').textContent = money(jobs.reduce((s, j) => s + due(j), 0));
}

function openDialog(job) {
  $('dialogTitle').textContent = job ? `تعديل الطلب #${job.number}` : 'استلام جهاز جديد';
  $('jobId').value = job ? job.id : '';
  for (const k of fields) $(k).value = job ? job[k] ?? '' : (k === 'price' || k === 'paid' ? '0' : k === 'status' ? 'تم الاستلام' : '');
  $('jobDialog').showModal();
  $('customer').focus();
}

$('jobForm').addEventListener('submit', (e) => {
  e.preventDefault();
  const data = Object.fromEntries(fields.map((k) => [k, $(k).value.trim()]));
  data.price = toNumber(data.price);
  data.paid = toNumber(data.paid);
  const id = $('jobId').value;
  if (id) {
    const j = jobs.find((x) => x.id === id);
    Object.assign(j, data, { updated: Date.now() });
  } else {
    jobs.push({ ...data, id: crypto.randomUUID ? crypto.randomUUID() : String(Date.now()), number: nextNumber(), created: Date.now(), updated: Date.now() });
  }
  save();
  $('jobDialog').close();
  render();
});

document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => $('jobDialog').close()));
$('newJobBtn').addEventListener('click', () => openDialog(null));
$('searchInput').addEventListener('input', render);
$('statusFilter').addEventListener('change', render);

function waPhone(p) {
  let d = p.replace(/[٠-٩]/g, (c) => '٠١٢٣٤٥٦٧٨٩'.indexOf(c)).replace(/\D/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  else if (d.startsWith('0')) d = (localStorage.getItem('salliha.cc') || '970') + d.slice(1);
  return d;
}

function openExternal(url) {
  // Electron/Capacitor route window.open to the system browser / WhatsApp app.
  window.open(url, '_blank');
}

function printReceipt(j) {
  const w = window.open('', '_blank', 'width=420,height=640');
  if (!w) return;
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  w.document.write(`<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><title>إيصال #${j.number}</title>
<style>body{font-family:system-ui,Tahoma,sans-serif;padding:16px;max-width:360px;margin:auto}h1{font-size:20px;text-align:center;margin:0}
p{margin:4px 0}hr{border:0;border-top:1px dashed #999;margin:10px 0}.c{text-align:center;color:#555;font-size:12px}</style>
<h1>صلّحها</h1><p class="c">إيصال استلام جهاز</p><hr>
<p><b>رقم الطلب:</b> #${j.number}</p><p><b>التاريخ:</b> ${new Date(j.created).toLocaleString('ar')}</p>
<p><b>العميل:</b> ${esc(j.customer)}</p><p><b>الهاتف:</b> ${esc(j.phone)}</p>
<p><b>الجهاز:</b> ${esc(j.device)}</p>${j.serial ? `<p><b>IMEI:</b> ${esc(j.serial)}</p>` : ''}
<p><b>العطل:</b> ${esc(j.issue)}</p><hr>
<p><b>السعر:</b> ${money(j.price)}</p><p><b>المدفوع:</b> ${money(j.paid)}</p><p><b>المتبقي:</b> ${money(due(j))}</p>
<p><b>الحالة:</b> ${esc(j.status)}</p><hr><p class="c">يرجى الاحتفاظ بهذا الإيصال لاستلام الجهاز</p>
<script>onload=()=>{print()}<\/script></html>`);
  w.document.close();
}

$('jobs').addEventListener('click', (e) => {
  const btn = e.target.closest('button[data-action]');
  if (!btn) return;
  const j = jobs.find((x) => x.id === btn.closest('.job-card').dataset.id);
  if (!j) return;
  switch (btn.dataset.action) {
    case 'edit': openDialog(j); break;
    case 'whatsapp': {
      const msg = `مرحباً ${j.customer}،\nتحديث طلب الصيانة #${j.number} (${j.device}):\nالحالة: ${j.status}` +
        (due(j) > 0 ? `\nالمبلغ المتبقي: ${money(due(j))}` : '') + '\nشكراً لثقتك — صلّحها';
      openExternal(`https://wa.me/${waPhone(j.phone)}?text=${encodeURIComponent(msg)}`);
      break;
    }
    case 'print': printReceipt(j); break;
    case 'delete':
      if (confirm(`حذف الطلب #${j.number} نهائياً؟`)) { jobs = jobs.filter((x) => x !== j); save(); render(); }
      break;
  }
});

// PWA install (browser only; hidden inside the desktop/mobile apps).
let deferredPrompt;
window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferredPrompt = e; $('installBtn').hidden = false; });
$('installBtn').addEventListener('click', async () => {
  if (!deferredPrompt) return;
  deferredPrompt.prompt(); await deferredPrompt.userChoice; deferredPrompt = null; $('installBtn').hidden = true;
});
if ('serviceWorker' in navigator && location.protocol.startsWith('http') && !window.Capacitor) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}

render();
