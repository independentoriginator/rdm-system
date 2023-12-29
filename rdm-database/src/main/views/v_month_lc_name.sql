create or replace view v_month_lc_name
as
select 
	l.tag as lang_code
	, set_config('lc_time', l.tag || '_' || l.default_country, true) as locale
	, m as n_month
	, to_char(to_date(m::text, 'mm'), 'mm') as s_month_mm					
	, to_char(to_date(m::text, 'mm'), 'mon') as s_month_mon
	, to_char(to_date(m::text, 'mm'), 'Mon') as s_month_mon_cap			
	, to_char(to_date(m::text, 'mm'), 'tmmonth') as s_month
	, to_char(to_date(m::text, 'mm'), 'tmMonth') as s_month_cap			
from 
	ng_rdm."language" l
	, generate_series(1, 12) m
where 
	l.default_country is not null
;

comment on view v_month_lc_name is 'Локализованные имена месяцев';
