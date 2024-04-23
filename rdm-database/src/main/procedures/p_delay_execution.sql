create or replace procedure p_delay_execution(
	i_delay_interval interval
	, i_max_run_time interval = null
	, i_start_timestamp timestamp = clock_timestamp()
)
language plpgsql
as $procedure$
begin
	perform	
		pg_catalog.pg_sleep_for(
			i_delay_interval
		)
	;
	
	if i_max_run_time is not null 
		and clock_timestamp() - i_start_timestamp >= i_max_run_time 
	then
		raise exception
			'Timeout occured'
		;
	end if;
end
$procedure$;

comment on procedure p_delay_execution(
	interval
	, interval
	, timestamp
) is 'Приостановить исполнение';