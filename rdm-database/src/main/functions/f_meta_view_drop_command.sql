create or replace function 
	f_meta_view_drop_command(
		i_meta_view_id ${mainSchemaName}.meta_view.id%type
		, i_cascade boolean = false
		, i_check_existence boolean = false
	)
returns text
language sql
stable
as $function$
select
	concat_ws(	
		E';\n'
		, case 
			when not v.is_matview_emulation
				or (
					v.view_oid is not null
					and v.view_type <> 'table'
				)
			then
				${mainSchemaName}.f_sys_obj_drop_command(
					i_obj_class => v.obj_class
					, i_obj_id => v.view_oid
					, i_cascade => i_cascade
					, i_check_existence => i_check_existence
				)
		end
		, (
			select 
				string_agg(
					${mainSchemaName}.f_sys_obj_drop_command(
						i_obj_class => p.obj_class
						, i_obj_id => p.obj_id
						, i_check_existence => true							
					)		
					, E';\n'
				)	
			from 
				${mainSchemaName}.v_sys_obj p
			where 
				p.obj_schema = v.schema_name
				and p.unqualified_name = v.mv_emulation_refresh_proc_name
		)
		, (
			select 
				string_agg(
					${mainSchemaName}.f_sys_obj_drop_command(
						i_obj_class => p.obj_class
						, i_obj_id => p.obj_id
						, i_check_existence => true							
					)		
					, E';\n'
				)	
			from 
				${mainSchemaName}.v_sys_obj p
			where 
				p.obj_schema = v.schema_name
				and p.unqualified_name = v.mv_emulation_table_func_name
		)
		, (
			select 
				concat_ws(
					E';\n'
					, string_agg(
						case 
							when current_table.obj_id is not null
								and not ('is_partition' = any(current_table.flags))
							then
								${mainSchemaName}.f_sys_obj_drop_command(
									i_obj_class => current_table.obj_class
									, i_obj_id => current_table.obj_id
									, i_check_existence => true							
								)
						end
						, E';\n'
					)
					, string_agg(
						case 
							when shadow_table.obj_id is not null
								and not ('is_partition' = any(shadow_table.flags))
							then
								${mainSchemaName}.f_sys_obj_drop_command(
									i_obj_class => shadow_table.obj_class
									, i_obj_id => shadow_table.obj_id
									, i_check_existence => true							
								)
						end
						, E';\n'
					)
					, format(
						'delete from ${stagingSchemaName}.materialized_view_partition where meta_view_id = %s'
						, p.meta_view_id
					)
				)
			from 
				${stagingSchemaName}.materialized_view_partition p
			left join ${mainSchemaName}.v_sys_obj current_table
				on current_table.obj_id = p.current_table_id
			left join ${mainSchemaName}.v_sys_obj shadow_table
				on shadow_table.obj_id = p.shadow_table_id
			where 
				p.meta_view_id = v.id
			group by 
				p.meta_view_id
		)
		, case 
			when not v.is_routine then
				format(
					'drop table if exists %I.%I'
					, v.schema_name
					, v.mv_emulation_filled_chunk_table_name
				)
		end
	)
from
	${mainSchemaName}.v_meta_view v
where 
	v.id = i_meta_view_id
$function$
;

comment on function 
	f_meta_view_drop_command(
		${mainSchemaName}.meta_view.id%type
		, boolean
		, boolean
	) 
	is 'Составление команды на удаление метапредставления'
;