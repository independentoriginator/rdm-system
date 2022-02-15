create or replace procedure p_build_target_api(
	i_type_rec record
)
language plpgsql
as $$
declare
	l_check_section text;
	l_insert_proc_section text;
	l_delete_proc_section text;
begin
	if i_type_rec.is_staging_table_generated = false then
		return;
	end if;
	
	if i_type_rec.is_temporal = false then
		l_check_section := '';
		
		l_insert_proc_section := 
			format(
				$insert_section$
				insert into 
					%I.%I(
						id, %s
					)
				select 
					coalesce(id, nextval('%I.%I_id_seq')), %s
				from 
					${stagingSchemaName}.%I t
				where 
					t.data_package_id = i_data_package_id
				on conflict (id) do update set
					record_date = l_state_change_date
					, %s	
				;
				$insert_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes		
				, i_type_rec.internal_name
				, i_type_rec.insert_expr_on_conflict_update_part
			);
	
		if i_type_rec.is_localization_table_generated = true then
			l_insert_proc_section := l_insert_proc_section || E'\n' || 
				format(
					$insert_section$
					insert into 
						%I.%I_lc(
							id
							, master_id
							, attr_id
							, lang_id
							, lc_string
							, is_default_value
						)
					with meta_attribute as (
						select *
						from ${database.defaultSchemaName}.v_meta_attribute a 
						where a.meta_type_name = '%I'
					)						
					select 
						coalesce(target_rec.id, nextval('%I.%I_lc_id_seq'))
						, master_rec.id as master_id
						, meta_attr.id as attr_id
						, p.lang_id
						, attr.attr_value as lc_string
						, true as is_default_value
					from 
						${stagingSchemaName}.%I t
					join ${stagingSchemaName}.data_package p 
						on p.id = t.data_package_id
					join %I.%I master_rec
						on master_rec.data_package_id = t.data_package_id
						and master_rec.data_package_rn = t.data_package_rn
					cross join lateral (
						values %s
					) attr(attr_name, attr_value)
					join meta_attribute meta_attr
						on meta_attr.internal_name = attr.attr_name
					left join %I.%I_lc target_rec
						on target_rec.master_id = master_rec.id
						and target_rec.attr_id = meta_attr.id
						and target_rec.lang_id = p.lang_id
						and target_rec.is_default_value = true
					where 
						t.data_package_id = i_data_package_id
						and attr.attr_value is not null
					on conflict (id) do update set
						lc_string = excluded.lc_string		
					;
					$insert_section$
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name					
					, i_type_rec.localisable_attr_values_list
					, i_type_rec.schema_name
					, i_type_rec.internal_name					
				);
		end if;
		
		l_delete_proc_section := 
			format(
				$delete_section$
				delete from
					%I.%I dest
				using 
					${stagingSchemaName}.%I src
				where 
					src.data_package_id = i_data_package_id
					and dest.id = src.id
				;
				$delete_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
			);
		
	else
		l_check_section :=
			format(
				$check_section$
				
				<<row_actuality_check>>
				declare 
					l_id %I.%I.id%%type;
				begin
					select 
						src.id
					into 
						l_id
					from 
						${stagingSchemaName}.%I src
					join %I.%I dest
						on dest.id = src.id
						and dest.version = src.version
						and dest.valid_to <> ${database.defaultSchemaName}.f_undefined_max_date() 
					where 
						src.data_package_id = i_data_package_id
					limit 1
					;
				
					if l_id is not null then
						raise exception 'The data package (id = %%) includes non-actual record version (id = %%)', i_data_package_id, l_id
							using hint = 'Try to recompile the data package';
					end if;
				end row_actuality_check;
				
				$check_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
			);
			
		l_insert_proc_section := 
			format(
				$insert_section$
				update
					%I.%I dest
				set 
					valid_to = l_state_change_date
				from 
					${stagingSchemaName}.%I src
				where 
					src.data_package_id = i_data_package_id
					and dest.id = src.id
					and dest.version = src.version
				;
					
				insert into 
					%I.%I(
						id
						, version
						, valid_from
						, valid_to
						, %s
					)
				select 
					coalesce(id, nextval('%I.%I_id_seq')) as id
					, nextval('%I.%I_version_seq') as version
					, l_state_change_date as valid_from
					, ${database.defaultSchemaName}.f_undefined_max_date() as valid_to
					, %s
				from 
					${stagingSchemaName}.%I t
				where 
					t.data_package_id = i_data_package_id
				;
				$insert_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes		
				, i_type_rec.internal_name
			);
			
		if i_type_rec.is_localization_table_generated = true then
			l_insert_proc_section := l_insert_proc_section || E'\n' || 
				format(
					$insert_section$
					insert into 
						%I.%I_lc(
							master_id
							, master_version
							, attr_id
							, lang_id
							, lc_string
							, is_default_value
						)
					with meta_attribute as (
						select *
						from ${database.defaultSchemaName}.v_meta_attribute a 
						where a.meta_type_name = '%I'
					)						
					select 
						master_rec.id as master_id
						, master_rec.version as master_version
						, meta_attr.id as attr_id
						, p.lang_id
						, attr.attr_value as lc_string
						, true as is_default_value
					from 
						${stagingSchemaName}.%I t
					join ${stagingSchemaName}.data_package p 
						on p.id = t.data_package_id
					join %I.%I master_rec
						on master_rec.data_package_id = t.data_package_id
						and master_rec.data_package_rn = t.data_package_rn
					cross join lateral (
						values %s
					) attr(attr_name, attr_value)
					join meta_attribute meta_attr
						on meta_attr.internal_name = attr.attr_name
					where 
						t.data_package_id = i_data_package_id
						and attr.attr_value is not null
					;
					$insert_section$
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name					
					, i_type_rec.schema_name
					, i_type_rec.internal_name					
					, i_type_rec.localisable_attr_values_list
				);
		end if;
			
		l_delete_proc_section := 
			format(
				$delete_section$
				update
					%I.%I dest
				set 
					valid_to = l_state_change_date
				from 
					${stagingSchemaName}.%I src
				where 
					src.data_package_id = i_data_package_id
					and dest.id = src.id
					and dest.version = src.version
				;
				$delete_section$
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
			);
	end if;
		
	execute format(
		$target_procedure$
		create or replace procedure %I.p_process_%I(
			i_data_package_id in ${stagingSchemaName}.data_package.id%%type
			, io_check_date in out ${stagingSchemaName}.data_package.state_change_date%%type
		)
		language plpgsql
		as $procedure$
		declare 
			l_data_package record;
			l_state_change_date timestamp without time zone := current_timestamp;
		begin
			select
				s.internal_name as state_name
				, p.state_change_date
				, p.is_deletion
			into 
				l_data_package
			from 
				${stagingSchemaName}.data_package p
			join ${database.defaultSchemaName}.data_package_state s on s.id = p.state_id
			where 
				p.id = i_data_package_id
			for update
			;
			
			if io_check_date <> l_data_package.state_change_date then
				raise exception 'The data package has changed since it was accessed: %%', l_data_package.state_change_date
					using hint = 'Try to repeat the operation';
  			end if;
  			
  			if l_data_package.state_name <> 'loaded' then  
				raise exception 'The data package has unexpected state: %%', l_data_package.state_name;
  			end if;
  			%s
  			if l_data_package.is_deletion = false then
  				%s
			else
				%s
			end if;
			%s				
			update 
				${stagingSchemaName}.data_package p
			set 
				state_id = (
					select 
						s.id
					from 
						${database.defaultSchemaName}.data_package_state s 
					where 
						s.internal_name = 'processed'
				)
				, state_change_date = l_state_change_date
			where 
				p.id = i_data_package_id
			;
			
			io_check_date := l_state_change_date;
		end
		$procedure$;
		$target_procedure$			
		, i_type_rec.schema_name
		, i_type_rec.internal_name
		, l_check_section
		, l_insert_proc_section
		, l_delete_proc_section
		, case 
			when exists (
				select 
					1 
				from
					pg_catalog.pg_proc p
				where 
					p.pronamespace = i_type_rec.schema_name::regnamespace
					and p.proname = 'p_after_processing_' || i_type_rec.internal_name
					and p.prokind = 'p'::"char"
					and 'i_data_package_id' = any(p.proargnames)
			) then format('
					call %I.p_after_processing_%I(
						i_data_package_id => i_data_package_id
					); 
				'
				, i_type_rec.schema_name 
				, i_type_rec.internal_name
			)
			else ''
		end
	);
end
$$;			
