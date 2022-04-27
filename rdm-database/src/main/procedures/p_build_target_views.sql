create or replace procedure p_build_target_views()
language plpgsql
as $procedure$
declare 
	l_view_rec record;
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
			coalesce(t.is_created, false) = false
		order by
			t.creation_order
			, t.dependency_level
		limit 1
		for update of meta_view
		;
		
		if l_view_rec is null then
			exit;
		end if;

   		raise notice 'Creating view %.%...', l_view_rec.schema_name, l_view_rec.internal_name;
	
		call ${mainSchemaName}.p_build_target_view(
			i_view_rec => l_view_rec
		);
	end loop;
end
$procedure$;			
