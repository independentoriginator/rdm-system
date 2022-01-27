create or replace procedure p_build_target_api(
	i_type_rec record
)
language plpgsql
as $$
declare 
	l_insert_proc_section text;
begin
	if i_type_rec.is_staging_table_generated = false then
		return;
	end if;
	
	if i_type_rec.is_temporal = false then
		if i_type_rec.is_localization_table_generated = true then
			l_insert_proc_section := 
				format(
					$insert_section$
					insert into 
						${database.defaultSchemaName}.%I(
							id, %s
						)
					select 
						coalesce(id, nextval('${database.defaultSchemaName}.%I_id_seq')), %s
					from 
						${stagingSchemaName}.%I t
					where 
						t.data_package_id = i_data_package_id
					on conflict (id) do update set
						%s	
					;

					insert into 
						${database.defaultSchemaName}.%I_lc(
							id
							, master_id
							, attr_id
							, lang_id
							, lc_string
							, is_default_value
						)
					select 
						coalesce(target_rec.id, nextval('${database.defaultSchemaName}.%I_lc_id_seq'))
						, mrs.id as master_id
						, meta_attr.id as attr_id
						, p.lang_id
						, attr.attr_value as lc_string
						, true as is_default_value
					from 
						${stagingSchemaName}.%I t
					join ${stagingSchemaName}.data_package p 
						on p.id = t.data_package_id
					join ${database.defaultSchemaName}.%I mrs
						on mrs.data_package_id = t.data_package_id
						and mrs.data_package_rn = t.data_package_rn
					cross join lateral (
						values %s
					) attr(attr_name, attr_value)
					join ${database.defaultSchemaName}.meta_type meta_type
						on meta_type.internal_name = '%I'
					join ${database.defaultSchemaName}.v_meta_attribute meta_attr
						on meta_attr.master_id = meta_type.id
						and meta_attr.internal_name = attr.attr_name
					left join ${database.defaultSchemaName}.%I_lc target_rec
						on target_rec.master_id = mrs.id
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
					, i_type_rec.internal_name
					, i_type_rec.non_localisable_attributes
					, i_type_rec.internal_name
					, i_type_rec.non_localisable_attributes		
					, i_type_rec.internal_name
					, i_type_rec.insert_expr_on_conflict_update_part
					, i_type_rec.internal_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name					
					, i_type_rec.localisable_attr_values_list
					, i_type_rec.internal_name
					, i_type_rec.internal_name					
				);
		end if;
	end if;
		
	execute format($target_procedure$
		create or replace procedure ${database.defaultSchemaName}.p_apply_%I(
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
  			
  			if l_data_package.state_name <> 'created' then  
				raise exception 'The data package has unexpected state: %%', l_data_package.state_name;
  			end if;
  			
  			if l_data_package.is_deletion = false then
  				%s
			else
				delete from
					${database.defaultSchemaName}.%I target_table
				where 
					exists (
						select 
							1
						from 
							${stagingSchemaName}.%I t
						where 
							t.data_package_id = i_data_package_id
							and t.id = target_table.id
					)
				;
			end if;
				
			update 
				${stagingSchemaName}.data_package p
			set 
				state_id = (
					select 
						s.id
					from 
						${database.defaultSchemaName}.data_package_state s 
					where 
						s.internal_name = 'applied'
				)
				, state_change_date = l_state_change_date
			where 
				p.id = i_data_package_id
			;
			
			io_check_date := l_state_change_date;
		end
		$procedure$;
		$target_procedure$			
		, i_type_rec.internal_name
		, l_insert_proc_section
		, i_type_rec.internal_name
		, i_type_rec.internal_name
	);
end
$$;			
