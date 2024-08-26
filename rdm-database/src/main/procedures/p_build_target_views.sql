drop procedure if exists 
	p_build_target_view(
		record
	)
;

drop procedure if exists 
	p_build_target_views(
	)
;

create or replace procedure 
	p_build_target_views(
		i_schema_name ${mainSchemaName}.meta_schema.internal_name%type = null
	)
language plpgsql
as $procedure$
declare 
	l_view_ids ${type.id}[];
	l_existing_view_ids ${type.id}[];
	l_views jsonb;
	l_schemas_to_create text;
	l_drop_command text;
	l_view_rec ${mainSchemaName}.v_meta_view;
	l_prev_view_id ${type.id};
	l_msg_text text;
	l_exception_detail text;
	l_exception_hint text;
	l_exception_context text;
	l_timestamp timestamp;
	l_start_timestamp timestamp := clock_timestamp();
	l_trigger_rec record;
begin
	select 
		array_agg(
			v.id
		) as ids
		, array_agg(
			v.id
		) filter(
			where
				not v.is_view_exists
		) as existing_view_ids
		, jsonb_agg(
			jsonb_build_object(
				'obj_name' 
				, v.internal_name
				, 'obj_schema'			
				, v.schema_name
				, 'obj_class'
				, v.obj_class
			)
		) filter(
			where
				not v.is_view_exists
		) as existing_views
		, string_agg(
			format('
				create schema if not exists %I
				'
				, v.schema_name
			) 
			|| case 
				when length('${mainEndUserRole}') > 0
				then 
					format('
						; grant usage on schema %I to ${mainEndUserRole}
						'
						, v.schema_name
					)
				else ''
			end
			, E';\n'
		) filter(
			where
				not v.is_schema_exists
		) as schemas_to_create
		, string_agg(
			concat_ws(	
				E';\n'
				, ${mainSchemaName}.f_sys_obj_drop_command(
					i_obj_class => v.obj_class
					, i_obj_id => v.view_oid
					, i_cascade => true
					, i_check_existence => true
				)
				, v.mv_emulation_refresh_procedures_drop_cmd
				, v.mv_emulation_partition_tables_drop_cmd
				, format(
					'drop table if exists %I.%I_chunk'
					, v.schema_name
					, v.internal_name
				)
			)
			, E';\n'
		) filter(
			where
				not v.is_routine
		) as drop_command
	into 
		l_view_ids
		, l_existing_view_ids
		, l_views
		, l_schemas_to_create
		, l_drop_command
	from (
		select 
			v.id
			, v.schema_name
			, v.internal_name
			, v.obj_class
			, v.is_routine
			, v.is_schema_exists
			, v.is_view_exists			
			, v.view_oid
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
			) as mv_emulation_refresh_procedures_drop_cmd
			, (
				select 
					concat_ws(
						E';\n'
						, string_agg(
							case 
								when current_table.obj_id is not null then
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
								when shadow_table.obj_id is not null then
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
			) as mv_emulation_partition_tables_drop_cmd
		from
			${mainSchemaName}.v_meta_view v
		join ${mainSchemaName}.meta_view mv 
			on mv.id = v.id
		where 
			(not coalesce(v.is_created, false) or mv.dependency_level is null)
			and not coalesce(v.is_disabled, false)
			and (v.schema_name = i_schema_name or i_schema_name is null)
	) v
	;

	if l_view_ids is null then
		return
		;
	end if
	;

	perform
	from 
		${mainSchemaName}.meta_view 
	where 
		id = any(l_view_ids)
	for update
	;

	if l_schemas_to_create is not null then
		raise notice 
			'Creating schemas...'
		;
		execute 
			l_schemas_to_create
		;	
	end if
	;

	if l_views is not null then
		raise notice 
			'Detecting and saving dependants before them dropping cascadly...'
		;
		
		l_timestamp := clock_timestamp();
	
		call 
			${mainSchemaName}.p_specify_meta_view_dependencies(
				i_views => l_views
				, i_treat_the_obj_as_dependent => false -- treat the object as master 
			)
		;
	
		raise notice 
			'Done in %.'
			, clock_timestamp() - l_timestamp
		;
	end if;

	if l_existing_view_ids is not null then
		raise notice 
			'Invalidating of the creation flag for dependent views (this matters for functions, that are not cascadly dropped)...'
		;
		with 
			dependent_view as (
				select 
					v.id
				from 
					${mainSchemaName}.meta_view_dependency dep
				join ${mainSchemaName}.meta_view v 
					on v.id = dep.view_id
					and v.is_created = true
					and v.is_external = false
				where 
					dep.master_view_id = any(l_existing_view_ids)
				for update of v
			)
		update 
			${mainSchemaName}.meta_view meta_view
		set 
			is_created = false
		from 
			dependent_view
		where
			dependent_view.id = meta_view.id
		;	
	end if;

	if l_drop_command is not null then
		raise notice 
			E'Dropping views that will be recreated... \n%'
			, l_drop_command
		;
		
		l_timestamp := clock_timestamp()
		;
	
		execute 
			l_drop_command
		;	 
	
		raise notice 
			'Done in %.'
			, clock_timestamp() - l_timestamp
		;
	end if
	;

	l_view_ids := array[]::${type.id}[]
	;
	l_views := '[]'::jsonb
	;

	raise notice 
		'Building target views...'
	;
	
	l_timestamp := clock_timestamp()
	;

	<<build_views>>
	loop
		select
			v.*
		into
			l_view_rec
		from 
			${mainSchemaName}.v_meta_view v
		join ${mainSchemaName}.meta_view meta_view 
			on meta_view.id = v.id
		where 
			not coalesce(v.is_created, false)
			and not coalesce(v.is_disabled, false)
			and (v.schema_name = i_schema_name or i_schema_name is null)
		order by
			case when v.is_external then null else v.creation_order end
			, v.previously_defined_dependency_level
		limit 1
		for update of meta_view
		;
		
		exit build_views when l_view_rec is null
		;
		
		if l_prev_view_id is not null and l_view_rec.id = l_prev_view_id 
		then
			raise exception 
				'The % was not processed for a some unexpected reason: %.%...'
				, l_view_rec.view_type
				, l_view_rec.schema_name
				, l_view_rec.internal_name
			;
		end if
		;
		
		l_prev_view_id = l_view_rec.id
		;
	
		if not l_view_rec.is_external 
			or not l_view_rec.is_routine
			or (
				not coalesce(l_view_rec.is_created, false) 
				and (
					not l_view_rec.is_external 
					or (
						-- an external object must be recreated within the current transaction only, during current dependencies recreation
						-- (if the object is deleted from the outside, then it should not be recreated)
						l_view_rec.is_external 
						and l_view_rec.modification_time = ${mainSchemaName}.f_current_timestamp() 
					)
				)
			)
		then
			begin
				raise notice 
					'Creating % %.%...'
					, l_view_rec.view_type
					, l_view_rec.schema_name
					, l_view_rec.internal_name
				;
				
				if l_view_rec.is_matview_emulation then
					call 
						${mainSchemaName}.p_build_matview_emulation(
							i_view_rec => l_view_rec  
						)
					;
				
					l_views := 
						l_views
						|| jsonb_build_object(
							'obj_name' 
							, l_view_rec.internal_name
							, 'obj_schema'			
							, l_view_rec.schema_name
							, 'obj_class'
							, l_view_rec.obj_class
							, 'attendants'
							, json_build_array((
								select 
									jsonb_build_object(
										'obj_name' 
										, p.obj_name
										, 'obj_schema'			
										, p.obj_schema
										, 'obj_class'
										, p.obj_class
									)
								from 
									${mainSchemaName}.v_meta_view v
								join ${mainSchemaName}.v_sys_obj p
									on p.obj_id = v.mv_emulation_refresh_proc_oid
								where
									v.id = l_view_rec.id									
							))
						)
					;
				
					for l_trigger_rec in (
						select
							t.*
						from 
							${mainSchemaName}.v_meta_trigger t
						where 
							t.meta_view_id = l_view_rec.id
						union all
						select 
							t.*
						from									
							${mainSchemaName}.meta_view_chunk_dependency dep
						join ${mainSchemaName}.v_meta_trigger t
							on t.meta_type_id = dep.master_type_id
						where 
							dep.view_id = l_view_rec.id
						union all
						select 
							t.*
						from									
							${mainSchemaName}.meta_view_chunk_dependency dep
						join ${mainSchemaName}.v_meta_trigger t
							on t.meta_view_id = dep.master_view_id
						where 
							dep.view_id = l_view_rec.id							
					) 
					loop
						call 
							${mainSchemaName}.p_build_target_trigger(
								i_trigger_rec => l_trigger_rec
							)
						;
					end loop
					;
				else
					execute 
						l_view_rec.query
					;
					
					l_views := 
						l_views
						|| jsonb_build_object(
							'obj_name' 
							, l_view_rec.internal_name
							, 'obj_schema'			
							, l_view_rec.schema_name
							, 'obj_class'
							, l_view_rec.obj_class
						)
					;
				end if
				;
			
				l_view_ids := l_view_ids || l_view_rec.id
				;					
			exception
				when others then
					get stacked diagnostics
						l_msg_text = MESSAGE_TEXT
						, l_exception_detail = PG_EXCEPTION_DETAIL
						, l_exception_hint = PG_EXCEPTION_HINT
						, l_exception_context = PG_EXCEPTION_CONTEXT
					;
					if l_view_rec.is_external then 
						raise notice 
							'External view %.% creation error: %: % (hint: %, context: %). The view will be disabled.'
							, l_view_rec.schema_name
							, l_view_rec.internal_name
							, l_msg_text
							, l_exception_detail
							, l_exception_hint
							, l_exception_context
						;
						update 
							${mainSchemaName}.meta_view 
						set 
							is_disabled = true
							, modification_time = ${mainSchemaName}.f_current_timestamp()
						where 
							id = l_view_rec.id
						;
					else
						raise exception 
							'View %.% creation error: %: % (hint: %, context: %)'
							, l_view_rec.schema_name
							, l_view_rec.internal_name
							, l_msg_text
							, l_exception_detail
							, l_exception_hint
							, l_exception_context
						;
					end if
					;	
			end
			;
		
			-- Main end user role
			if not l_view_rec.is_external 
				and length('${mainEndUserRole}') > 0 
			then
				execute	
					format(
						'grant %s %I.%s to ${mainEndUserRole}'
						, case when l_view_rec.is_routine then 'execute on routine ' else 'select on' end
						, l_view_rec.schema_name
						, l_view_rec.internal_name 
					)
				;
			end if
			;
		
			update 
				${mainSchemaName}.meta_view v
			set 
				is_created = true
				, is_valid = false
			where 
				id = l_view_rec.id
			;
		
		elsif l_view_rec.is_external 
			and not l_view_rec.is_view_exists
			and (l_view_rec.modification_time <> ${mainSchemaName}.f_current_timestamp() or l_view_rec.modification_time is null)	
		then
			raise notice 
				'Disabling non-actual external view %.%...'
				, l_view_rec.schema_name
				, l_view_rec.internal_name
			;
			
			update 
				${mainSchemaName}.meta_view 
			set 
				is_disabled = true
				, modification_time = ${mainSchemaName}.f_current_timestamp()
			where 
				id = l_view_rec.id
			;
		end if
		;
	end loop build_views
	;

	raise notice 
		'Done in %.'
		, clock_timestamp() - l_timestamp
	;

	raise notice 
		E'Actualizing stored dependencies...\n%'
		, l_views
	;
	
	l_timestamp := clock_timestamp()
	;

	call 
		${mainSchemaName}.p_specify_meta_view_dependencies(
			i_views => l_views
			, i_treat_the_obj_as_dependent => true 
			, i_consider_registered_objects_only => true
		)
	;

	raise notice 
		'Done in %.'
		, clock_timestamp() - l_timestamp
	;

	update 
		${mainSchemaName}.meta_view v
	set 
		dependency_level = 
			coalesce((
					select 
						max(dep.level)
					from 
						${mainSchemaName}.meta_view_dependency dep
					where
						dep.view_id = v.id
						and dep.master_view_id is not null		
				)
				, 0
			)
		, modification_time = ${mainSchemaName}.f_current_timestamp()
	where 
		id = any(l_view_ids)
	;

	raise notice 
		'Total time spent: %.'
		, clock_timestamp() - l_start_timestamp
	;
end
$procedure$
;	

comment on procedure 
	p_build_target_views(
		${mainSchemaName}.meta_schema.internal_name%type
	) is 'Генерация целевых представлений'
;
