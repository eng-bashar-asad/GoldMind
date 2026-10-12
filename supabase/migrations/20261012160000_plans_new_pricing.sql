-- New pricing (owner's decision 2026-10-12): Basic 6 users $4,200/yr, Professional 10 users $6,600/yr,
-- Custom (price on request: hardware installation + integration, e-invoicing). "Business" retired.
alter table public.plans add column if not exists highlights_ar text[];
update public.plans set included_staff = 6, price_yearly = 4200, extra_staff_price = 600, staff_upgrade_threshold = 9, next_plan_key = 'pro',
  prices = '{"USD":{"yearly":4200,"quarterly":1155,"extra_staff_yearly":600,"einvoice_addon_monthly":27,"einvoice_overage":0.27},"AED":{"yearly":15425,"quarterly":4240,"extra_staff_yearly":2205,"einvoice_addon_monthly":99,"einvoice_overage":1}}'::jsonb,
  features = '{"einvoice":false,"voice_input":false,"custom_tables":false,"profit_report":true,"ai_photo_entry":false}'::jsonb,
  highlights_ar = array['المبيعات والمشتريات والمخزون والصندوق','حسابات الزبائن والتجار وكشوفاتهم','تقارير الأرباح والتقارير المالية','الدخول بالبصمة والتحقق بخطوتين']
 where key = 'basic';
update public.plans set included_staff = 10, price_yearly = 6600, extra_staff_price = 550, staff_upgrade_threshold = 14, next_plan_key = 'enterprise',
  einvoice_monthly_quota = 300,
  prices = '{"USD":{"yearly":6600,"quarterly":1815,"extra_staff_yearly":550,"einvoice_overage":0.27},"AED":{"yearly":24240,"quarterly":6665,"extra_staff_yearly":2020,"einvoice_overage":1}}'::jsonb,
  features = '{"einvoice":true,"voice_input":true,"custom_tables":true,"profit_report":true,"ai_photo_entry":true}'::jsonb,
  highlights_ar = array['كل ما في الباقة الأساسية','الإدخال بالصورة والصوت (AI)','جداول مخصصة','الجرد بـ RFID والماس والصيانة']
 where key = 'pro';
update public.plans set is_active = false, next_plan_key = null where key = 'business';
update public.plans set name_ar = 'الخاصة', name_en = 'Custom', sort_order = 3,
  highlights_ar = array['عدد المستخدمين والفروع حسب حاجتك','تركيب وربط الأجهزة بالبرنامج: طابعات الفواتير، طابعات الباركود، مسدس الجرد','الفوترة الإلكترونية مشمولة','تدريب الموظفين ودعم مباشر']
 where key = 'enterprise';
-- Custom plan: 20 users included (owner's decision)
update public.plans set included_staff = 20,
  highlights_ar = array['20 مستخدماً، والفروع حسب حاجتك','تركيب وربط الأجهزة بالبرنامج: طابعات الفواتير، طابعات الباركود، مسدس الجرد','الفوترة الإلكترونية مشمولة','تدريب الموظفين ودعم مباشر']
 where key = 'enterprise';
