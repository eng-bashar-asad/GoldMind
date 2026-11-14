-- A piece reserved by a deposit (عربون) can be sold to the customer who reserved it; selling it clears
-- the reservation. (The sale screen already offers such a piece for that customer; the server refused it.)
-- Patches post_sale_invoice in place: two exact text replacements, refused if either is not found.
do $$
declare def text := pg_get_functiondef('public.post_sale_invoice(jsonb)'::regprocedure);
        a text := 'if pc.status <> ''available'' then raise exception';
        b text := 'update pieces set status = ''sold'' where id in';
begin
  if position(a in def) = 0 or position(b in def) = 0 then
    raise exception 'post_sale_invoice changed — patch not applied';
  end if;
  def := replace(def, a, 'if pc.status <> ''available'' and not (pc.status = ''reserved'' and cust is not null and pc.reserved_customer_id = cust) then raise exception');
  def := replace(def, b, 'update pieces set status = ''sold'', reserved_customer_id = null where id in');
  execute def;
end $$;
