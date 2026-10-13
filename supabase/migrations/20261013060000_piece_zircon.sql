-- Zircon weight on gold pieces (separate from diamonds Di / Cs), printed on the
-- barcode label as "Z:x.xxg" through a new label field type.
-- Contains DROP CONSTRAINT (replaced right away with a wider one, no data removed) — run by the owner.

alter table public.pieces add column if not exists zircon_carat numeric
  check (zircon_carat is null or zircon_carat >= 0);
comment on column public.pieces.zircon_carat is 'Zircon (cubic zirconia) weight in grams; label symbol Z.';

alter table public.zebra_label_fields drop constraint if exists zebra_label_fields_content_type_check;
alter table public.zebra_label_fields add constraint zebra_label_fields_content_type_check
  check (content_type = any (array['barcode_number','barcode_graphic','company_name','weight','karat','mc',
                                   'description','custom_text','blank_line','diamond_carat','zircon_carat']));
