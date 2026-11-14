# Generates the demo-company seed: one DO block per day, every operation through the real RPCs,
# then each event's rows are moved to its date/time (all rows in a block start with created_at = now()).
import json, random, os
random.seed(7)
S = '481681c1-bbd2-4d3f-98a7-0362ac0da632'
U = '92164ef6-df33-43d1-a5a7-d66199974ec5'
OUT = os.path.dirname(__file__)
IMG = lambda i: f'https://images.unsplash.com/photo-{i}?w=800&q=80&fm=jpg'
PH = {
 'خاتم': ['1598560917807-1bae44bd2be8','1603561596973-8166e9e089d1','1611955167811-4711904bb9f8','1631982690223-8aa4be0a2497','1689367436629-1d288f1e23b6','1713950920412-97799efdf870','1784822041171-13e87aebc1bf'],
 'محبس': ['1622398925373-3f91b1e275f5'],
 'حلق': ['1653227907864-560dce4c252d','1671644730555-916aa8d8157f','1701777892740-88419a701472','1651160670627-2896ddf7822f','1615655114865-4cc1bda5901e','1617038260897-41a1f14a8ca0','1626784215021-2e39ccf971cd','1723802205505-2f88b2227718'],
 'سلسال': ['1783541507490-edb026e2a961','1685970731194-e27b477e87ba','1773929345739-94db8a4ccd0c','1569397288884-4d43d6738fbd','1786052337650-9e1c0dd01f5e','1623321673989-830eff0fd59f'],
 'عقد': ['1771734065116-61e16b353ded','1722410180644-5955f83ec8b1'],
 'إسوارة': ['1602173574767-37ac01994b2a','1777999802051-f6f0296e76af','1778000000743-87e855360c51','1626784215013-13322cb0e471'],
 'مباريم': ['1786052347285-3ad7f12c738f','1679156271456-d6068c543ee7','1611107683227-e9060eccd846'],
 'طقم': ['1722410180687-b05b50922362','1758995115857-2de1eb6283d0'],
}
WT = {'خاتم': (2.5, 6.5), 'محبس': (3.5, 7), 'حلق': (2.2, 6), 'سلسال': (4, 11), 'عقد': (14, 32), 'إسوارة': (6, 16), 'مباريم': (18, 40), 'طقم': (35, 70)}
STYLE = ['نقشة ورد', 'سادة لامع', 'مخرّم', 'مرصّع زركون', 'نقشة شامية', 'تصميم إيطالي', 'كارتييه', 'نقشة تركية', 'مطفي ولامع', 'حبات', 'موديل خليجي', 'سحب يدوي', 'فراشة', 'قلب', 'تاج', 'هلال', 'كلاسيك', 'ناعم']
BOX = {'خاتم': 'فترينة الخواتم', 'محبس': 'فترينة الخواتم', 'حلق': 'فترينة الحلق', 'سلسال': 'فترينة السلاسل', 'عقد': 'فترينة السلاسل', 'إسوارة': 'فترينة الأساور', 'مباريم': 'فترينة الأساور', 'طقم': 'خزنة الأطقم'}
used = set(); photo_i = {k: 0 for k in PH}
def piece(t, k, fab):
    while True:
        d = t + ' ' + random.choice(STYLE) + ' ' + str(k) + 'K'
        if d not in used: used.add(d); break
        d = None
    w = round(random.uniform(*WT[t]), 2)
    aw = round(w - random.uniform(0.05, 0.6), 2) if random.random() < 0.3 else w
    ph = PH[t][photo_i[t] % len(PH[t])]; photo_i[t] += 1
    return dict(t=t, k=k, w=w, aw=aw, fab=fab, d=d, photo=IMG(ph), box=BOX[t])

PRICE = {24: 459.0, 22: 420.8, 21: 401.6, 18: 344.3}
DRIFT = [0, 2.1, -1.4, 3.2, 4.0, 1.1, -2.3, 0.6, 2.8, 3.5]  # AED/g 24K change per day
def price(day, k): return round((PRICE[24] + DRIFT[day]) * k / 24, 2)

CUST = ['سلمى الزعابي', 'مريم الشامسي', 'خالد المهيري', 'عائشة النعيمي', 'سيف الكتبي', 'شيخة المري', 'عبدالله الظاهري', 'موزة السويدي', 'حمدان الفلاسي', 'لطيفة الحمادي', 'راشد البلوشي', 'نوف العامري', 'ماجد الرميثي', 'حصة المنصوري', 'سعيد الجابري', 'ميثاء الكعبي', 'عمر الحوسني', 'جواهر الطنيجي', 'منصور الشحي', 'دانة اليماحي', 'طارق المزروعي', 'ريتا خوري', 'جورجيت عازار', 'وفاء السيد', 'كريم منصور']
PHONE = {c: '05' + random.choice('024568') + ''.join(random.choice('0123456789') for _ in range(7)) for c in CUST}
TR = {'R': 'مؤسسة الرواسي للذهب', 'B': 'مشغل بيت الصاغة', 'Y': 'الياقوت للمعادن الثمينة', 'N': 'مجموعة النخبة للمجوهرات'}
WS = 'ورشة الصفوة للتصنيع'
CATS = ['إيجار المحل', 'كهرباء ومياه', 'ضيافة', 'رواتب', 'صيانة', 'مواصلات', 'تسويق وإعلان']

days = ['2026-11-04','2026-11-05','2026-11-06','2026-11-07','2026-11-08','2026-11-09','2026-11-10','2026-11-11','2026-11-12','2026-11-13']
q = lambda s: "'" + str(s).replace("'", "''") + "'"
J = lambda o: q(json.dumps(o, ensure_ascii=False)) + '::jsonb'

stock = []      # descriptions of pieces on hand (available)
reserved = {}   # desc -> customer
blocks = []
cust_made = set()

class Day:
    def __init__(s, i): s.i = i; s.sql = []; s.date = days[i]
    def ev(s, hm, *stmts):
        s.sql += list(stmts)
        s.sql.append(f"perform pg_temp.gm_shift({q(S)}, (((now() at time zone 'Asia/Dubai')::date - {10 - s.i}) + time {q(hm)}) at time zone 'Asia/Dubai');")
    def cust(s, name):
        if name in cust_made: return f"(select id from customers where store_id={q(S)} and name={q(name)})"
        cust_made.add(name)
        s.sql.append(f"insert into customers (store_id, name, phone, phone_country_code) values ({q(S)}, {q(name)}, {q(PHONE[name])}, '+971');")
        return f"(select id from customers where store_id={q(S)} and name={q(name)})"
    def done(s):
        p = [f"-- {s.date}", "do $d$ declare r jsonb; v uuid; begin",
             f"perform set_config('request.jwt.claims', json_build_object('sub', {q(U)}, 'role', 'authenticated')::text, true);",
             "execute $f$ create or replace function pg_temp.gm_shift(sid uuid, ts timestamptz) returns void language plpgsql as $g$ declare t text; begin "
             "foreach t in array array['cash_movements','customer_debts','daily_cash_log','piece_movements','trader_movements'] loop "
             "execute format('update public.%I set created_at=$1, entered_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; end loop; "
             "foreach t in array array['customer_deposits','customers','customer_phones','expense_entries','gold_stock_lots','invoices','pieces','stock_vouchers','stock_parties','traders','piece_intake_batches','piece_lot_draws','trader_scrap_draws','audit_log'] loop "
             "begin execute format('update public.%I set created_at=$1 where store_id=$2 and created_at=now()', t) using ts, sid; exception when undefined_column or undefined_table then null; end; end loop; "
             "update public.gold_prices set updated_at = ts where store_id = sid and updated_at = now(); end $g$ $f$;"]
        p += s.sql
        p.append("end $d$;")
        body = '\n'.join(p).replace("declare r jsonb; v uuid;", "declare r jsonb; v uuid; S uuid := " + q(S) + ";")
        head, rest = body.split("\n", 3)[:3], body.split("\n", 3)[3]
        blocks.append('\n'.join(head) + '\n' + rest.replace(q(S), 'S'))

def pid(desc): return f"(select id from pieces where store_id={q(S)} and description_ar={q(desc)} limit 1)"
def tid(k): return f"(select id from traders where store_id={q(S)} and name={q(TR[k])})"
WSID = f"(select id from stock_parties where store_id={q(S)} and name={q(WS)})"
def cat(n): return f"(select id from expense_categories where store_id={q(S)} and name={q(n)})"
def setprices(d, day):
    return [f"insert into gold_prices (store_id, karat, price_per_gram, mode) values ({q(S)}, {k}, {price(day, k)}, 'manual') on conflict (store_id, karat) do update set price_per_gram = excluded.price_per_gram, updated_at = now();" for k in (24, 22, 21, 18)]

def expense(d, hm, c, amt, note):
    d.ev(hm, f"perform cash_voucher(jsonb_build_object('store_id', {q(S)}, 'kind', 'out', 'party', 'expense', 'category_id', {cat(c)}, 'amount', {amt}, 'notes', {q(note)}));")
def trader_pay(d, hm, k, amt, note, method='cash'):
    d.ev(hm, f"perform cash_voucher(jsonb_build_object('store_id', {q(S)}, 'kind', 'out', 'party', 'trader', 'party_id', {tid(k)}, 'amount', {amt}, 'method', {q(method)}, 'notes', {q(note)}));")
def receive(d, hm, k, items, ref, note):
    lines = [dict(kind='piece', karat=p['k'], weight=p['w'], acc_weight=p['aw'], fab_per_gram=p['fab'], description_ar=p['d'], box_name=p['box']) for p in items]
    d.ev(hm, f"perform trader_receive_stock({tid(k)}, {J(lines)}, 0, {q(ref)}, {q(note)});",
         *[f"update pieces set photo_url={q(p['photo'])}, piece_type={q(p['t'])} where store_id={q(S)} and description_ar={q(p['d'])};" for p in items])
    stock.extend(p['d'] for p in items)
PIECES = {}
def mk(t, k, fab):
    p = piece(t, k, fab); PIECES[p['d']] = p; return p
def sale_price(day, p, markup):
    return round(p['w'] * price(day, p['k']) + p['w'] * markup, 0)
def sale(d, hm, cname, descs, method, day, cash=None, bank=0, markup=None):
    c = d.cust(cname)
    items = []
    tot = 0
    for ds in descs:
        p = PIECES[ds]; m = markup or random.choice([28, 32, 35, 40, 45, 55])
        pr = sale_price(day, p, m); tot += pr
        items.append(f"jsonb_build_object('mode','manual','piece_id',{pid(ds)},'barcode',(select barcode from pieces where id={pid(ds)}),'karat',{p['k']},'weight',{p['w']},'price',{pr},'description',{q(ds)})")
        if ds in stock: stock.remove(ds)
    if bank == 'rest': bank = tot - cash
    pay = f", 'cash_paid', {cash}, 'bank_paid', {bank or 0}" if method == 'mixed' else ''
    d.ev(hm, f"r := post_sale_invoice(jsonb_build_object('store_id', {q(S)}, 'client_ref', gen_random_uuid(), 'customer_id', {c}, 'payment_method', {q(method)}{pay}, 'confirm_low_price', true, 'items', jsonb_build_array({', '.join(items)})));")
    return tot
def pick(types=None, k=None):
    c = [x for x in stock if x not in reserved and (not types or PIECES[x]['t'] in types) and (not k or PIECES[x]['k'] == k)]
    if not c: c = [x for x in stock if x not in reserved and (not k or PIECES[x]['k'] == k)] or [x for x in stock if x not in reserved]
    x = random.choice(c); return x

# ---------- Day 0: setup + first deliveries ----------
d = Day(0)
d.sql += setprices(d, 0)
for n in CATS: d.sql.append(f"perform save_expense_category({q(S)}, {q(n)});")
d.ev('09:00',
     *[f"insert into traders (store_id, name, phone, phone_country_code, notes) values ({q(S)}, {q(TR[k])}, {q('04' + str(3300000 + i * 1371))}, '+971', {q(n)});" for i, (k, n) in enumerate([('R', 'مورّد قطع 18 و21 — مصنعية متوسطة'), ('B', 'مشغل محلي — أطقم وعقود بمصنعية عالية'), ('Y', 'مورّد خواتم وحلق — دفع نقدي'), ('N', 'ذهب خام بالجملة للتصنيع')])],
     f"insert into stock_parties (store_id, name, kind) values ({q(S)}, {q(WS)}, 'intermediary');")
d.ev('09:20', f"insert into daily_cash_log (store_id, operation_type, direction, amount, currency, notes, created_by) values ({q(S)}, 'رصيد افتتاحي', 'in', 60000, 'AED', 'رصيد بداية الصندوق', (select id from staff where user_id={q(U)}));")
R1 = [mk(t, k, f) for t, k, f in [('خاتم',18,9),('خاتم',18,9),('خاتم',21,8),('محبس',21,8),('حلق',18,11),('حلق',18,11),('حلق',21,10),('سلسال',18,12),('سلسال',21,10),('إسوارة',21,10),('إسوارة',18,12),('خاتم',18,9),('سلسال',18,12),('حلق',21,10)]]
receive(d, '10:15', 'R', R1, 'R-7781', 'استلام بضاعة — دفعة افتتاح')
B1 = [mk(t, k, f) for t, k, f in [('طقم',21,22),('طقم',21,24),('عقد',21,18),('عقد',18,20),('مباريم',21,16),('مباريم',21,16),('إسوارة',21,15),('سلسال',21,14),('عقد',21,18),('حلق',21,15)]]
receive(d, '11:40', 'B', B1, 'BS-0412', 'استلام أطقم وعقود')
d.ev('12:30', f"perform trader_receive_stock({tid('N')}, {J([dict(kind='bulk', karat=21, weight=220, acc_weight=220, fab_per_gram=0, box_name='كسر 21')])}, 0, 'N-220', 'ذهب خام 21 للتصنيع');")
expense(d, '13:00', 'إيجار المحل', 9500, 'إيجار شهر تشرين الثاني')
d.ev('17:10', f"perform cash_voucher(jsonb_build_object('store_id', {q(S)}, 'kind', 'out', 'party', 'expense', 'category_id', {cat('تسويق وإعلان')}, 'amount', 1200, 'method', 'bank', 'notes', 'إعلانات انستغرام'));")
d.done()

# ---------- Day 1 ----------
d = Day(1); d.sql += setprices(d, 1)
sale(d, '10:40', 'سلمى الزعابي', [pick(['خاتم'])], 'cash', 1)
d.ev('11:30', f"perform stock_out_to_party_v2({WSID}, '{{}}'::uuid[], 'تسليم ذهب خام لتصنيع أساور وسلاسل', null, {J([dict(karat=21, weight=160)])});")
sale(d, '13:05', 'مريم الشامسي', [pick(['حلق'])], 'bank', 1)
sale(d, '17:45', 'خالد المهيري', [pick(['طقم'])], 'mixed', 1, cash=5000, bank='rest')
expense(d, '18:20', 'ضيافة', 140, 'قهوة وحلويات للزبائن')
sale(d, '20:10', 'عائشة النعيمي', [pick(['سلسال']), pick(['حلق'])], 'cash', 1)
d.done()

def deposit(d, hm, cname, desc, amt):
    c = d.cust(cname); reserved[desc] = cname
    items = f"jsonb_build_array(jsonb_build_object('barcode',(select barcode from pieces where id={pid(desc)}),'description',{q(desc)},'karat',{PIECES[desc]['k']},'weight',{PIECES[desc]['w']}))"
    d.ev(hm, f"perform create_customer_deposit(jsonb_build_object('store_id', {q(S)}, 'customer_id', {c}, 'amount', {amt}, 'method', 'cash', 'to_cashbox', true, 'items', {items}, 'notes', 'حجز لحين استكمال المبلغ'));")
def cust_pay(d, hm, cname, amt, method='cash', note='دفعة من الرصيد'):
    c = d.cust(cname)
    d.ev(hm, f"perform cash_voucher(jsonb_build_object('store_id', {q(S)}, 'kind', 'in', 'party', 'customer', 'party_id', {c}, 'amount', {amt}, 'method', {q(method)}, 'notes', {q(note)}));")
def ws_in(d, hm, items, scrap_back, note):
    lines = [dict(karat=p['k'], weight=p['w'], acc_weight=p['aw'], fab_per_gram=p['fab'], description_ar=p['d'], piece_type=p['t'], photo_url=p['photo'], box_name=p['box'], color='Gold') for p in items]
    if scrap_back: lines.append(dict(karat=21, weight=scrap_back, acc_weight=scrap_back, fab_per_gram=0, to_scrap=True))
    d.ev(hm, f"perform stock_in_from_party({WSID}, '{{}}'::uuid[], {J(lines)}, {q(note)}, 'قطع ذهبية', '{{}}'::uuid[]);")
    stock.extend(p['d'] for p in items)

# ---------- Day 2 (Nov 6): workshop returns pieces made from the raw gold ----------
d = Day(2); d.sql += setprices(d, 2)
W1 = [mk(t, 21, f) for t, f in [('إسوارة',12),('إسوارة',12),('إسوارة',12),('سلسال',14),('سلسال',14),('خاتم',10),('خاتم',10),('حلق',11),('مباريم',9),('سلسال',14)]]
# scale the ten pieces to ~151 g of the 160 g sent; 6.4 g comes back as scrap, ~2.6 g is workshop loss
tot = sum(p['w'] for p in W1); f = 151.2 / tot
for p in W1: p['w'] = round(p['w'] * f, 2); p['aw'] = p['w']
ws_in(d, '11:15', W1, 6.4, 'تصنيع من الذهب الخام (سند الإخراج السابق) — 10 قطع + كسر راجع')
sale(d, '12:20', 'سيف الكتبي', [pick(['محبس', 'خاتم'])], 'cash', 2)
DEP1 = pick(['طقم'])
deposit(d, '15:40', 'شيخة المري', DEP1, 3000)
sale(d, '18:05', 'عبدالله الظاهري', [pick(['إسوارة'], 21)], 'bank', 2)
expense(d, '19:30', 'كهرباء ومياه', 1850, 'فاتورة ديوا')
sale(d, '21:15', 'موزة السويدي', [pick(['حلق']), pick(['خاتم'])], 'mixed', 2, cash=1500, bank='rest')
d.done()

# ---------- Day 3 (Nov 7): cash purchase invoice from a trader; a sale left partly on account ----------
d = Day(3); d.sql += setprices(d, 3)
Y1 = [mk(t, 18, 20) for t in ['خاتم', 'خاتم', 'حلق', 'حلق', 'سلسال', 'خاتم']]
items = [dict(mode='piece', karat=p['k'], weight=p['w'], fab_fee=round(p['w'] * p['fab'], 2), price=round(p['w'] * (price(3, 18) + p['fab']), 2), description=p['d'], box_name=p['box']) for p in Y1]
d.ev('10:30', f"r := post_purchase_invoice(jsonb_build_object('store_id', {q(S)}, 'client_ref', gen_random_uuid(), 'type', 'buyTrader', 'payment_method', 'cash', 'trader_id', {tid('Y')}, 'items', {J(items)}));",
     *[f"update pieces set photo_url={q(p['photo'])}, piece_type={q(p['t'])}, accounting_weight_grams=weight_grams where store_id={q(S)} and description_ar={q(p['d'])};" for p in Y1])
stock.extend(p['d'] for p in Y1)
sale(d, '13:10', 'حمدان الفلاسي', [pick(['مباريم'])], 'mixed', 3, cash=6000, bank=0)   # rest stays on his account
sale(d, '16:45', 'لطيفة الحمادي', [pick(['سلسال'], 18)], 'cash', 3)
d.ev('17:25', f"perform trader_gold_to_cash({tid('R')}, 9, 21, {price(3, 21)}, 'we_owe_gold', 'تسكير جزء من الذهب نقداً');")
trader_pay(d, '17:30', 'R', 2500, 'دفعة على حساب المصنعية')
sale(d, '20:40', 'راشد البلوشي', [pick(['خاتم'], 18)], 'bank', 3)
d.done()

# ---------- Day 4 (Nov 8): deposit used on the sale; scrap bought from a customer ----------
d = Day(4); d.sql += setprices(d, 4)
sale(d, '11:00', 'شيخة المري', [DEP1], 'credit', 4)  # the 3,000 deposit pays part, the rest below
d.ev('11:05', f"perform cash_voucher(jsonb_build_object('store_id', {q(S)}, 'kind', 'in', 'party', 'customer', 'party_id', {d.cust('شيخة المري')}, 'amount', (select total_amount - amount_paid from invoices where store_id={q(S)} and customer_id={d.cust('شيخة المري')} and type='sale' order by created_at desc limit 1), 'method', 'bank', 'notes', 'باقي ثمن الطقم بالبطاقة'));")
reserved.pop(DEP1, None)
items = [dict(mode='bulk', karat=21, weight=12.6, price=round(12.6 * (price(4, 21) - 6), 2), description='كسر 21 — أساور قديمة')]
d.ev('12:40', f"r := post_purchase_invoice(jsonb_build_object('store_id', {q(S)}, 'client_ref', gen_random_uuid(), 'type', 'buyRetail', 'payment_method', 'cash', 'counterparty_name', 'نوف العامري', 'seller_id_type', 'emirates_id', 'seller_id_number', '784-1990-4471235-2', 'items', {J(items)}));")
sale(d, '15:20', 'نوف العامري', [pick(['إسوارة'], 21)], 'cash', 4)
expense(d, '16:00', 'مواصلات', 85, 'توصيل طلبية')
sale(d, '19:55', 'ماجد الرميثي', [pick(['خاتم']), pick(['سلسال'])], 'cash', 4)
sale(d, '21:30', 'حصة المنصوري', [pick(['عقد'])], 'bank', 4)
d.done()

# ---------- Day 5 (Nov 9): a piece to the workshop to resize; scrap settles a trader's gold ----------
d = Day(5); d.sql += setprices(d, 5)
resize = pick(['خاتم'], 21)
d.ev('10:20', f"perform stock_out_to_party_v2({WSID}, array[{pid(resize)}], 'تصغير مقاس الخاتم', null, '[]'::jsonb);")
stock.remove(resize)
d.ev('11:10', f"perform give_scrap_to_trader({tid('N')}, 21, 15.0, 'تسديد ذهب من صندوق الكسر');")
sale(d, '13:30', 'سعيد الجابري', [pick(['حلق'])], 'cash', 5)
cust_pay(d, '14:15', 'حمدان الفلاسي', 1500, 'cash', 'دفعة أولى من باقي فاتورة المباريم')
expense(d, '15:00', 'ضيافة', 95, 'ماء وعصائر')
sale(d, '18:40', 'ميثاء الكعبي', [pick(['عقد'])], 'mixed', 5, cash=8000, bank='rest')
sale(d, '20:25', 'عمر الحوسني', [pick(['سلسال'])], 'cash', 5)
d.done()

# ---------- Day 6 (Nov 10): resized ring back; salaries ----------
d = Day(6); d.sql += setprices(d, 6)
d.ev('11:30', f"perform stock_in_from_party({WSID}, array[{pid(resize)}], '[]'::jsonb, 'رجع الخاتم بعد التصغير', 'فترينة الخواتم', '{{}}'::uuid[]);")
stock.append(resize)
sale(d, '12:50', 'جواهر الطنيجي', [pick(['إسوارة'])], 'bank', 6)
sale(d, '16:10', 'منصور الشحي', [pick(['خاتم']), pick(['خاتم'])], 'cash', 6)
expense(d, '17:00', 'رواتب', 7200, 'رواتب الموظفين — دفعة نصف الشهر')
d.ev('18:10', f"perform trader_gold_to_cash({tid('B')}, 12, 21, {price(6, 21)}, 'we_owe_gold', 'تسكير جزء من الذهب نقداً');")
trader_pay(d, '18:15', 'B', 6000, 'دفعة من حساب المصنعية', 'bank')
sale(d, '21:05', 'دانة اليماحي', [pick(['حلق']), pick(['سلسال'])], 'mixed', 6, cash=2000, bank='rest')
d.done()

# ---------- Day 7 (Nov 11): second delivery from a trader ----------
d = Day(7); d.sql += setprices(d, 7)
B2 = [mk(t, k, f) for t, k, f in [('عقد',21,19),('طقم',21,23),('مباريم',21,17),('إسوارة',18,16),('سلسال',18,15),('حلق',18,14),('خاتم',21,13),('إسوارة',21,15)]]
receive(d, '10:45', 'B', B2, 'BS-0433', 'استلام الدفعة الثانية')
sale(d, '13:15', 'طارق المزروعي', [pick(['خاتم'], 21)], 'cash', 7)
sale(d, '17:40', 'ريتا خوري', [pick(['عقد'])], 'mixed', 7, cash=4000, bank='rest')
expense(d, '18:30', 'صيانة', 450, 'صيانة إضاءة الفترينات')
sale(d, '20:50', 'سلمى الزعابي', [pick(['حلق'])], 'bank', 7)
d.done()

# ---------- Day 8 (Nov 12) ----------
d = Day(8); d.sql += setprices(d, 8)
sale(d, '11:25', 'جورجيت عازار', [pick(['إسوارة'])], 'cash', 8)
deposit(d, '13:00', 'وفاء السيد', pick(['مباريم']), 2000)
cust_pay(d, '14:30', 'حمدان الفلاسي', 1000, 'bank', 'دفعة ثانية')
sale(d, '16:55', 'كريم منصور', [pick(['محبس', 'خاتم']), pick(['محبس', 'خاتم'])], 'cash', 8)
trader_pay(d, '18:00', 'R', 3000, 'دفعة على الحساب')
sale(d, '20:35', 'عائشة النعيمي', [pick(['سلسال'])], 'mixed', 8, cash=1000, bank='rest')
d.done()

# ---------- Day 9 (Nov 13) ----------
d = Day(9); d.sql += setprices(d, 9)
R2 = [mk(t, k, f) for t, k, f in [('خاتم',18,9),('خاتم',21,8),('خاتم',18,10),('محبس',21,8),('محبس',18,9),('حلق',18,11),('حلق',21,10),('حلق',18,12),('سلسال',18,12),('سلسال',21,11),('إسوارة',21,10),('إسوارة',18,13),('عقد',21,17),('مباريم',21,15),('طقم',18,26),('سلسال',18,12)]]
receive(d, '09:45', 'R', R2, 'R-7802', 'استلام الدفعة الثانية — تجديد الفترينة')
sale(d, '10:50', 'خالد المهيري', [pick(['خاتم'])], 'bank', 9)
sale(d, '13:40', 'مريم الشامسي', [pick(['طقم'])], 'mixed', 9, cash=10000, bank='rest')
expense(d, '15:10', 'ضيافة', 120, 'ضيافة')
sale(d, '17:25', 'سيف الكتبي', [pick(['إسوارة'])], 'cash', 9)
trader_pay(d, '18:40', 'B', 2000, 'دفعة على حساب المصنعية')
sale(d, '21:10', 'لطيفة الحمادي', [pick(['حلق']), pick(['سلسال', 'إسوارة'])], 'cash', 9)
d.done()

if __name__ == '__main__':
    head = open(os.path.join(OUT, 'bisan_reset_head.sql')).read()
    out = head + '\n\n' + '\n\n'.join(blocks) + '\n'
    open(os.path.join(OUT, 'bisan-demo-reset.sql'), 'w').write(out)
    print(len(out))
