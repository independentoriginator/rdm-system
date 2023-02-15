create or replace procedure p_build_target_views()
language plpgsql
as $procedure$
declare 
	l_view_rec record;
	l_prev_view_id ${mainSchemaName}.meta_view.id%type;
	l_msg_text text;
	l_exception_detail text;
	l_exception_hint text;
	l_exception_context text;
begin
	while true
	loop
		select
			t.*
		into
			l_view_rec
		from 
			${mainSchemaName}.v_meta_view t
		join ${mainSchemaName}.meta_view meta_view 
			on meta_view.id = t.id
		where 
			(coalesce(t.is_created, false) = false or meta_view.dependency_level is null)
			and coalesce(t.is_disabled, false) = false
		order by
			t.is_external
			, t.creation_order
			, t.previously_defined_dependency_level
		limit 1
		for update of meta_view
		;
		
		if l_view_rec is null then
			exit;
		end if;
		
		if l_prev_view_id is not null then
			if l_view_rec.id = l_prev_view_id then 
				raise 'The view was not processed for a some unexpected reason: %.%...', l_view_rec.schema_name, l_view_rec.internal_name;
			end if;
		end if;
		
		l_prev_view_id = l_view_rec.id;
		
   		raise notice 'Creating view %.%...', l_view_rec.schema_name, l_view_rec.internal_name;
	
		call ${mainSchemaName}.p_build_target_view(
			i_view_rec => l_view_rec
		);
	end loop;
exception
when others then
	get stacked diagnostics
		l_msg_text = MESSAGE_TEXT
		, l_exception_detail = PG_EXCEPTION_DETAIL
		, l_exception_hint = PG_EXCEPTION_HINT
		, l_exception_context = PG_EXCEPTION_CONTEXT
		;
	raise exception 
		E'View %.% creation error: %\n%\n(hint: %,\ncontext: %)'
		, l_view_rec.schema_name
		, l_view_rec.internal_name		
		, l_msg_text
		, l_exception_detail
		, l_exception_hint
		, l_exception_context
		;
end
$procedure$;			
