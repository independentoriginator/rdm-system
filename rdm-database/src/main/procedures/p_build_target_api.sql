create or replace procedure 
	p_build_target_api(
		i_type_rec record
	)
language plpgsql
as $$
declare
	l_check_section text;
	l_insert_proc_section text;
	l_delete_proc_section text;
	l_cte_option text := 
		case 
			when ${mainSchemaName}.f_is_server_feature_available('cte_explicitly_materializing') 
			then 'materialized ' 
			else '' 
		end
	;
begin
	if i_type_rec.is_staging_table_generated = false then
		return
		;
	end if
	;
	if i_type_rec.is_temporal = false then
		l_check_section := ''
		;
		l_insert_proc_section := 
			format(
				E'l_row_offset := 0'
				'\n;'
				'\n<<data_insertion>>'
				'\nloop'
				'\n	insert into' 
				'\n		%I.%I('
				'\n			id, %s'
				'\n		)'
				'\n	select' 
				'\n		coalesce(id, nextval(''%I.%I_id_seq'')), %s'
				'\n	from' 
				'\n		${stagingSchemaName}.%I t'
				'\n	where' 
				'\n		t.data_package_id = i_data_package_id'
				'\n		and t.data_package_rn between l_row_offset + 1 and l_row_offset + l_row_limit'
				'\n	on conflict (id) do update set'
				'\n		record_date = l_state_change_date'
				'\n		, %s'	
				'\n	;'
				'\n	l_row_offset := l_row_offset + l_row_limit'
				'\n	;'
				'\n	if l_row_offset >= l_data_package_row_count then'
				'\n		exit data_insertion'
				'\n		;'
				'\n	end if'
				'\n	;'
				'\nend loop data_insertion'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes		
				, i_type_rec.internal_name
				, i_type_rec.insert_expr_on_conflict_update_part
			)
		;
	
		if i_type_rec.is_localization_table_generated then
			l_insert_proc_section := 
				l_insert_proc_section
				|| format(
					E'\n;'
					'\nl_row_offset := 0'
					'\n;'
					'\n<<localisable_data_insertion>>'
					'\nloop'
					'\n	with' 
					'\n		package_data as %s('
					'\n			select' 
					'\n				t.id'
					'\n				, t.data_package_id'
					'\n				, t.data_package_rn'
					'\n				, %s'
					'\n			from' 								
					'\n				${stagingSchemaName}.%I t'
					'\n			where' 
					'\n				t.data_package_id = i_data_package_id'
					'\n				and t.data_package_rn between l_row_offset + 1 and l_row_offset + l_row_limit'
					'\n		)'
					'\n		, meta_attribute as %s('
					'\n			select' 
					'\n				*'
					'\n			from' 
					'\n				${mainSchemaName}.v_meta_attribute a' 
					'\n			where' 
					'\n				a.meta_type_name = ''%I'''
					'\n				and a.is_localisable'
					'\n		)'						
					'\n		, localisable_data as %s('
					'\n			select' 
					'\n				target_rec.id'
					'\n				, master_rec.id as master_id'
					'\n				, meta_attr.id as attr_id'
					'\n				, p.lang_id'
					'\n				, case meta_attr.internal_name'
					'\n					%s'
					'\n				end as lc_string'
					'\n				, true as is_default_value'
					'\n			from' 
					'\n				package_data t'
					'\n			cross join meta_attribute meta_attr'
					'\n			join ${stagingSchemaName}.data_package p' 
					'\n				on p.id = t.data_package_id'
					'\n			join %I.%I master_rec'
					'\n				on master_rec.data_package_id = t.data_package_id'
					'\n				and master_rec.data_package_rn = t.data_package_rn'
					'\n			left join %I.%I_lc target_rec'
					'\n				on target_rec.master_id = master_rec.id'
					'\n				and target_rec.attr_id = meta_attr.id'
					'\n				and target_rec.lang_id = p.lang_id'
					'\n				and target_rec.is_default_value'
					'\n		)' 
					'\n		, deleted_data as %s('
					'\n			delete from' 
					'\n				%I.%I_lc dest'
					'\n			using'
					'\n				localisable_data src'
					'\n			where' 
					'\n				dest.id = src.id'
					'\n				and src.lc_string is null'
					'\n			returning'
					'\n				dest.id as deleted_id'
					'\n		)'
					'\n	insert into' 
					'\n		%I.%I_lc('
					'\n			id'
					'\n			, master_id'
					'\n			, attr_id'
					'\n			, lang_id'
					'\n			, lc_string'
					'\n			, is_default_value'
					'\n		)'
					'\n	select' 
					'\n		coalesce(src.id, nextval(''%I.%I_lc_id_seq'')) as id'
					'\n		, src.master_id'
					'\n		, src.attr_id'
					'\n		, src.lang_id'
					'\n		, src.lc_string'
					'\n		, src.is_default_value'
					'\n	from' 
					'\n		localisable_data src'
					'\n	left join deleted_data d'
					'\n		on d.deleted_id = src.id'
					'\n	where' 
					'\n		src.lc_string is not null'
					'\n	on conflict (id) do update set'
					'\n		lc_string = excluded.lc_string'		
					'\n	;'
					'\n	l_row_offset := l_row_offset + l_row_limit'
					'\n	;'
					'\n	if l_row_offset >= l_data_package_row_count then'
					'\n		exit localisable_data_insertion'
					'\n	;'
					'\n	end if'
					'\n	;'
					'\nend loop localisable_data_insertion'
					, l_cte_option
					, i_type_rec.localisable_attributes
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.localisable_attr_case_expr_body
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
				)
			;
		end if
		;
		l_delete_proc_section := 
			format(
				E'delete from'
				'\n	%I.%I dest'
				'\nusing' 
				'\n	${stagingSchemaName}.%I src'
				'\nwhere' 
				'\n	src.data_package_id = i_data_package_id'
				'\n	and dest.id = src.id'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
			)
		;
	else
		l_check_section :=
			format(
				E'\n<<row_actuality_check>>'
				'\ndeclare'
				'\n	l_id %I.%I.id%%type;'
				'\nbegin'
				'\n	select' 
				'\n		src.id'
				'\n	into' 
				'\n		l_id'
				'\n	from' 
				'\n		${stagingSchemaName}.%I src'
				'\n	join %I.%I dest'
				'\n		on dest.id = src.id'
				'\n		and dest.version = src.version'
				'\n		and dest.valid_to <> ${mainSchemaName}.f_undefined_max_date()' 
				'\n		and dest.external_version is null' 
				'\n		and dest.meta_version is null' 
				'\n	where' 
				'\n		src.data_package_id = i_data_package_id'
				'\n	limit 1'
				'\n	;'
				'\n	if l_id is not null then'
				'\n		raise exception' 
				'\n			''%I.%I: the data package (id = %%) includes non-actual record version (id = %%)'''
				'\n			, i_data_package_id'
				'\n			, l_id'
				'\n			using hint = ''Try to recompile the data package'''
				'\n		;'
				'\n	end if'
				'\n	;'
				'\nend row_actuality_check'
				'\n;'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
			)			
		;
		l_insert_proc_section := 
			format(
				E'update'
				'\n	%I.%I dest'
				'\nset' 
				'\n	valid_to = l_state_change_date'
				'\nfrom' 
				'\n	${stagingSchemaName}.%I src'
				'\nwhere' 
				'\n	src.data_package_id = i_data_package_id'
				'\n	and dest.id = src.id'
				'\n	and dest.version = src.version'
				'\n	and dest.external_version is null' 
				'\n	and dest.meta_version is null' 
				'\n;'
				'\nl_row_offset := 0'
				'\n;'			
				'\n<<data_insertion>>'
				'\nloop'
				'\n	with' 
				'\n		package_data as %s('
				'\n			select' 
				'\n				t.id'
				'\n				, t.version'
				'\n				, t.valid_from'
				'\n				, t.valid_to'
				'\n				, %s'
				'\n				, row_number()' 
				'\n					over('
				'\n						partition by'
				'\n							t.external_id'
				'\n							, t.meta_id'
				'\n						order by'
				'\n							t.external_id'
				'\n							, t.external_version_ordinal_num'
				'\n							, t.meta_id'
				'\n							, t.meta_version_ordinal_num'
				'\n							, t.valid_from'
				'\n					)' 
				'\n					as version_ordinal_num'
				'\n			from' 								
				'\n				${stagingSchemaName}.%I t'
				'\n			where' 
				'\n				t.data_package_id = i_data_package_id'
				'\n				and t.data_package_rn between l_row_offset + 1 and l_row_offset + l_row_limit'									
				'\n		)'
				'\n		, closed_old_external_versions as %s('
				'\n			with' 
				'\n				external_versions as ('
				'\n					select' 
				'\n						dest.id'
				'\n						, dest.version'
				'\n						, src.valid_from as valid_to'
				'\n					from' 
				'\n						%I.%I dest'
				'\n					join package_data src'
				'\n						on src.data_package_id = i_data_package_id'
				'\n						and src.external_id = dest.external_id'
				'\n						and src.source_id = dest.source_id'
				'\n						and src.version_ordinal_num = 1'
				'\n						and src.external_version is not null' 
				'\n						and src.valid_from is not null'
				'\n					where' 
				'\n						dest.valid_to = ('
				'\n							select' 
				'\n								max(t.valid_to)'
				'\n							from' 
				'\n								%I.%I t'
				'\n							where' 
				'\n								t.external_id = src.external_id'
				'\n								and t.source_id = src.source_id'
				'\n								and t.valid_from < src.valid_from' 
				'\n						)'
				'\n						and dest.external_version is not null' 
				'\n						and (dest.data_package_id <> i_data_package_id or dest.data_package_id is null)'
				'\n					order by' 
				'\n						dest.version'
				'\n					for update of dest'
				'\n				)'
				'\n			update'
				'\n				%I.%I t'
				'\n			set' 
				'\n				valid_to = ev.valid_to'
				'\n			from' 
				'\n				external_versions ev'
				'\n			where' 
				'\n				t.id = ev.id'
				'\n				and t.version = ev.version'
				'\n			returning' 
				'\n				t.id'
				'\n				, t.version'
				'\n		)'
				'\n		, closed_old_meta_versions as %s('
				'\n			with' 
				'\n				meta_versions as ('
				'\n					select' 
				'\n						dest.id'
				'\n						, dest.version'
				'\n						, src.valid_from as valid_to'
				'\n					from' 
				'\n						%I.%I dest'
				'\n					join package_data src'
				'\n						on src.data_package_id = i_data_package_id'
				'\n						and src.meta_id = dest.meta_id'
				'\n						and src.source_id = dest.source_id'
				'\n						and src.version_ordinal_num = 1'
				'\n						and src.meta_version is not null' 
				'\n						and src.external_id is null'
				'\n						and src.valid_from is not null'
				'\n					where' 
				'\n						dest.valid_to = ('
				'\n							select' 
				'\n								max(t.valid_to)'
				'\n							from' 
				'\n								%I.%I t'
				'\n							where' 
				'\n								t.meta_id = src.meta_id'
				'\n								and t.source_id = src.source_id'
				'\n								and t.valid_from < src.valid_from' 
				'\n						)'
				'\n						and dest.meta_version is not null'
				'\n						and dest.external_id is null'
				'\n						and (dest.data_package_id <> i_data_package_id or dest.data_package_id is null)'
				'\n					order by' 
				'\n						dest.version'
				'\n					for update of dest'
				'\n				)'
				'\n			update'
				'\n				%I.%I t'
				'\n			set' 
				'\n				valid_to = mv.valid_to'
				'\n			from' 
				'\n				meta_versions mv'
				'\n			where' 
				'\n				t.id = mv.id'
				'\n				and t.version = mv.version'
				'\n			returning' 
				'\n				t.id'
				'\n				, t.version'
				'\n		)'
				'\n		, initial_versions as %s('
				'\n			insert into' 
				'\n				%I.%I('
				'\n					id'
				'\n					, version'
				'\n					, valid_from'
				'\n					, valid_to'
				'\n					, record_date'
				'\n					, %s'
				'\n				)'
				'\n			select' 
				'\n				coalesce('
				'\n					t.id'
				'\n					, ('
				'\n						select'
				'\n							e.id'
				'\n						from'
				'\n							%I.%I e' 
				'\n						where' 
				'\n							e.external_id = t.external_id'
				'\n							and e.source_id = t.source_id'
				'\n						order by' 
				'\n							e.valid_from desc'
				'\n						limit 1'
				'\n					)'
				'\n					, ('
				'\n						select'
				'\n							e.id'
				'\n						from' 
				'\n							%I.%I e' 
				'\n						where' 
				'\n							t.external_id is null' 
				'\n							and e.meta_id = t.meta_id'
				'\n							and e.source_id = t.source_id'
				'\n						order by' 
				'\n							e.valid_from desc'
				'\n						limit 1'
				'\n					)'
				'\n					, nextval(''%I.%I_id_seq'')'
				'\n				) as id'
				'\n				, coalesce('
				'\n					case' 
				'\n						when t.external_version is not null'
				'\n							or t.meta_version is not null' 
				'\n						then t.version'
				'\n					end'
				'\n					, nextval(''%I.%I_version_seq'')'
				'\n				) as version'
				'\n				, coalesce('
				'\n					t.valid_from'
				'\n					, case'
				'\n						when t.id is null then' 
				'\n							coalesce('
				'\n								('
				'\n									select'
				'\n										e.valid_to'
				'\n									from' 
				'\n										%I.%I e' 
				'\n									where' 
				'\n										e.external_id = t.external_id'
				'\n										and e.source_id = t.source_id'
				'\n									order by' 
				'\n										e.external_version_ordinal_num desc'
				'\n										, e.valid_from desc'
				'\n									limit 1'
				'\n								)'
				'\n								, ('
				'\n									select'
				'\n										e.valid_to'
				'\n									from' 
				'\n										%I.%I e' 
				'\n									where' 
				'\n										t.external_id is null' 
				'\n										and e.meta_id = t.meta_id'
				'\n										and e.source_id = t.source_id'
				'\n									order by' 
				'\n										e.meta_version_ordinal_num desc'
				'\n										, e.valid_from desc'
				'\n									limit 1'
				'\n								)'
				'\n								, ${mainSchemaName}.f_undefined_min_date()'
				'\n							)'
				'\n						else' 
				'\n							l_state_change_date'
				'\n					end'
				'\n				) as valid_from'
				'\n				, coalesce('
				'\n					t.valid_to'
				'\n					, ${mainSchemaName}.f_undefined_max_date()'
				'\n				) as valid_to'
				'\n				, l_state_change_date'
				'\n				, %s'
				'\n			from' 
				'\n				package_data t'
				'\n			left join closed_old_external_versions oev'
				'\n				on false'
				'\n			left join closed_old_meta_versions omv'
				'\n				on false'
				'\n			where' 
				'\n				t.version_ordinal_num = 1'
				'\n			on conflict (id, version) do update set'
				'\n				record_date = l_state_change_date'
				'\n				, valid_from = excluded.valid_from'
				'\n				, valid_to = excluded.valid_to'
				'\n				, %s'	
				'\n			returning'
				'\n				id as inserted_id'
				'\n				, version as inserted_version'
				'\n				, external_id as inserted_external_id'
				'\n				, external_version as inserted_external_version'
				'\n				, meta_id as inserted_meta_id'
				'\n				, meta_version as inserted_meta_version'
				'\n		)'
				'\n	insert into' 
				'\n		%I.%I('
				'\n			id'
				'\n			, version'
				'\n			, valid_from'
				'\n			, valid_to'
				'\n			, record_date'
				'\n			, %s'
				'\n		)'
				'\n	select' 
				'\n		t.id'
				'\n		, coalesce('
				'\n			case' 
				'\n				when t.external_version is not null'
				'\n					or t.meta_version is not null' 
				'\n				then t.version'
				'\n			end'
				'\n			, nextval(''%I.%I_version_seq'')'
				'\n		) as version'
				'\n		, coalesce('
				'\n			t.valid_from'
				'\n			, l_state_change_date'
				'\n		) as valid_from'
				'\n		, coalesce('
				'\n			t.valid_to'
				'\n			, ${mainSchemaName}.f_undefined_max_date()'
				'\n		) as valid_to'
				'\n		, l_state_change_date'
				'\n		, %s'
				'\n	from ('						
				'\n		select' 
				'\n			iv.inserted_id as id'
				'\n			, t.version'
				'\n			, t.valid_from'
				'\n			, t.valid_to'
				'\n			, %s'
				'\n		from' 								
				'\n			package_data t'
				'\n		join initial_versions iv' 
				'\n			on iv.inserted_external_id = t.external_id'
				'\n		where'
				'\n			t.version_ordinal_num > 1'
				'\n			and t.external_id is not null'
				'\n		union all'
				'\n		select' 
				'\n			iv.inserted_id as id'
				'\n			, t.version'
				'\n			, t.valid_from'
				'\n			, t.valid_to'
				'\n			, %s'
				'\n		from' 								
				'\n			package_data t'
				'\n		join initial_versions iv' 
				'\n			on iv.inserted_meta_id = t.meta_id'
				'\n		where'
				'\n			t.version_ordinal_num > 1'
				'\n			and t.external_version is null'
				'\n			and t.meta_version is not null'
				'\n	) t'
				'\n	order by' 
				'\n		t.external_id'
				'\n		, t.external_version_ordinal_num'
				'\n		, t.meta_id'
				'\n		, t.meta_version_ordinal_num'
				'\n		, t.valid_from'
				'\n	on conflict (id, version) do update set'
				'\n		record_date = l_state_change_date'
				'\n		, valid_from = excluded.valid_from'
				'\n		, valid_to = excluded.valid_to'
				'\n		, %s'	
				'\n	;'
				'\n	l_row_offset := l_row_offset + l_row_limit'
				'\n	;'
				'\n	if l_row_offset >= l_data_package_row_count then'
				'\n		exit data_insertion'
				'\n		;'
				'\n	end if'
				'\n	;'
				'\nend loop data_insertion'
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
				, l_cte_option
				, i_type_rec.non_localisable_attributes
				, i_type_rec.internal_name
				, l_cte_option
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, l_cte_option
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, l_cte_option
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
 				, i_type_rec.insert_expr_on_conflict_update_part
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.schema_name
				, i_type_rec.internal_name
				, i_type_rec.non_localisable_attributes
				, i_type_rec.non_localisable_attributes
				, i_type_rec.non_localisable_attributes
 				, i_type_rec.insert_expr_on_conflict_update_part
			)
		;
			
		if i_type_rec.is_localization_table_generated then
			l_insert_proc_section := 
				l_insert_proc_section
				|| format(
					E'\n;'
					'\nl_row_offset := 0'
					'\n;'
					'\n<<localisable_data_insertion>>'
					'\nloop'
					'\n	with' 
					'\n		package_data as %s('
					'\n			select' 
					'\n				t.id'
					'\n				, t.version'
					'\n				, t.valid_from'
					'\n				, t.valid_to'
					'\n				, t.data_package_id'
					'\n				, t.data_package_rn'
					'\n				, %s'
					'\n			from' 								
					'\n				${stagingSchemaName}.%I t'
					'\n			where' 
					'\n				t.data_package_id = i_data_package_id'
					'\n				and t.data_package_rn between l_row_offset + 1 and l_row_offset + l_row_limit'
					'\n		)'
					'\n		, meta_attribute as %s('
					'\n			select' 
					'\n				*'
					'\n			from' 
					'\n				${mainSchemaName}.v_meta_attribute a' 
					'\n			where' 
					'\n				a.meta_type_name = ''%I'''
					'\n				and a.is_localisable'
					'\n		)'	
					'\n		, localisable_data as %s('
					'\n			select' 
					'\n				target_rec.id'
					'\n				, master_rec.id as master_id'
					'\n				, master_rec.version as master_version'
					'\n				, meta_attr.id as attr_id'
					'\n				, p.lang_id'
					'\n				, case meta_attr.internal_name'
					'\n					%s'
					'\n				end as lc_string'
					'\n				, true as is_default_value'
					'\n			from' 
					'\n				package_data t'
					'\n			cross join meta_attribute meta_attr'
					'\n			join ${stagingSchemaName}.data_package p' 
					'\n				on p.id = t.data_package_id'
					'\n			join %I.%I master_rec'
					'\n				on master_rec.data_package_id = t.data_package_id'
					'\n				and master_rec.data_package_rn = t.data_package_rn'
					'\n			left join %I.%I_lc target_rec'
					'\n				on target_rec.master_id = master_rec.id'
					'\n				and target_rec.master_version = master_rec.version'
					'\n				and target_rec.attr_id = meta_attr.id'
					'\n				and target_rec.lang_id = p.lang_id'
					'\n				and target_rec.is_default_value'
					'\n		)' 
					'\n		, deleted_data as %s('
					'\n			delete from' 
					'\n				%I.%I_lc dest'
					'\n			using'
					'\n				localisable_data src'
					'\n			where' 
					'\n				dest.id = src.id'
					'\n				and src.lc_string is null'
					'\n			returning' 
					'\n				dest.id as deleted_id'
					'\n		)'
					'\n	insert into' 
					'\n		%I.%I_lc('
					'\n			id'
					'\n			, master_id'
					'\n			, master_version'
					'\n			, attr_id'
					'\n			, lang_id'
					'\n			, lc_string'
					'\n			, is_default_value'
					'\n		)'
					'\n	select' 
					'\n		coalesce(src.id, nextval(''%I.%I_lc_id_seq'')) as id'
					'\n		, src.master_id'
					'\n		, src.master_version'
					'\n		, src.attr_id'
					'\n		, src.lang_id'
					'\n		, src.lc_string'
					'\n		, src.is_default_value'
					'\n	from' 
					'\n		localisable_data src'
					'\n	left join deleted_data d'
					'\n		on d.deleted_id = src.id'
					'\n	where' 
					'\n		src.lc_string is not null'
					'\n	on conflict (id) do update set'
					'\n		lc_string = excluded.lc_string'		
					'\n	;'
					'\n	l_row_offset := l_row_offset + l_row_limit'
					'\n	;'
					'\n	if l_row_offset >= l_data_package_row_count then'
					'\n		exit localisable_data_insertion'
					'\n		;'
					'\n	end if'
					'\n	;'
					'\nend loop localisable_data_insertion'
					, l_cte_option
					, i_type_rec.localisable_attributes
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.internal_name
					, l_cte_option
					, i_type_rec.localisable_attr_case_expr_body
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, l_cte_option					
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.schema_name
					, i_type_rec.internal_name
				)
			;
		end if
		;
			
		l_delete_proc_section := 
			concat_ws(
				E'\n;\n'
				, format(
					E'update'
					'\n	%I.%I dest'
					'\nset' 
					'\n	valid_to = l_state_change_date'
					'\nfrom' 
					'\n	${stagingSchemaName}.%I src'
					'\nwhere' 
					'\n	src.data_package_id = i_data_package_id'
					'\n	and dest.id = src.id'
					'\n	and dest.version = src.version'
					'\n	and dest.external_version is null' 
					'\n	and dest.meta_version is null' 
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name
				)
				, case 
					when i_type_rec.is_localization_table_generated then
						format(
							E'delete from'
							'\n	%I.%I_lc dest_lc'
							'\nusing' 
							'\n	${stagingSchemaName}.%I src'
							'\njoin %I.%I dest'
							'\n	on dest.id = src.id'
							'\n	and dest.version = src.version'
							'\n	and ('
							'\n		dest.external_version is not null' 
							'\n		or dest.meta_version is not null'
							'\n	)'
							'\nwhere' 
							'\n	src.data_package_id = i_data_package_id'
							'\n	and dest_lc.master_id = dest.id'
							'\n	and dest_lc.master_version = dest.version'
							, i_type_rec.schema_name
							, i_type_rec.internal_name
							, i_type_rec.internal_name
							, i_type_rec.schema_name
							, i_type_rec.internal_name
						) 
				end
				, format(
					E'delete from'
					'\n	%I.%I dest'
					'\nusing' 
					'\n	${stagingSchemaName}.%I src'
					'\nwhere' 
					'\n	src.data_package_id = i_data_package_id'
					'\n	and dest.id = src.id'
					'\n	and dest.version = src.version'
					'\n	and ('
					'\n		dest.external_version is not null' 
					'\n		or dest.meta_version is not null'
					'\n	)'
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.internal_name
				)
			)
		;
	end if
	;
		
	execute 
		format(
			E'create or replace procedure'
			'\n	%I.p_process_%I('
			'\n		i_data_package_id in ${stagingSchemaName}.data_package.id%%type'
			'\n		, io_check_date in out ${stagingSchemaName}.data_package.state_change_date%%type'
			'\n	)'
			'\nlanguage plpgsql'
			'\nsecurity definer'
			'\nas $procedure$'
			'\ndeclare' 
			'\n	l_data_package record;'
			'\n	l_state_change_date timestamp without time zone := ${mainSchemaName}.f_current_timestamp();'
			'\n	l_data_package_row_count bigint;'
			'\n	l_row_limit bigint := ${mainSchemaName}.f_operation_row_limit();'
			'\n	l_row_offset bigint;'
			'\nbegin'
			'\n	select'
			'\n		s.internal_name as state_name'
			'\n		, p.state_change_date'
			'\n		, p.is_deletion'
			'\n		, p.type_id'
			'\n	into' 
			'\n		l_data_package'
			'\n	from' 
			'\n		${stagingSchemaName}.data_package p'
			'\n	join ${mainSchemaName}.data_package_state s on s.id = p.state_id'
			'\n	where' 
			'\n		p.id = i_data_package_id'
			'\n	for update of p'
			'\n	;'
			'\n	if io_check_date <> l_data_package.state_change_date then'
			'\n		raise exception'
			'\n			''The data package has changed since it was accessed: %%'''
			'\n			, l_data_package.state_change_date'
			'\n		using hint = ''Try to repeat the operation'''
			'\n		;'
	  		'\n	end if'
	  		'\n	;'
	  		'\n	if l_data_package.state_name <> ''loaded'' then'  
			'\n		raise exception'
			'\n			''The data package is in an unexpected state: %%'''
			'\n			, l_data_package.state_name'
			'\n		;'
	  		'\n	end if'
	  		'\n	;'
	  		'\n	select' 
	  		'\n		count(*)'
	  		'\n	into'
	  		'\n		l_data_package_row_count'
			'\n	from' 
			'\n		${stagingSchemaName}.%I src'
			'\n	where' 
			'\n		src.data_package_id = i_data_package_id'
			'\n	;'
			'\n	if l_data_package_row_count > 0 then'
			'\n		call'
			'\n			${mainSchemaName}.p_invalidate_entity_dependent_views('
			'\n				i_type_id => l_data_package.type_id' 
			'\n			)'
			'\n		;%s'
		  	'\n		if l_data_package.is_deletion = false then'
		  	'\n			%s'
			'\n			;'
			'\n		else'
			'\n			%s'
			'\n			;'
			'\n		end if'
			'\n		;'
			'\n		%s'
			'\n		;'
			'\n	end if'
			'\n	;'
			'\n	update' 
			'\n		${stagingSchemaName}.data_package p'
			'\n	set' 
			'\n		state_id = ('
			'\n			select' 
			'\n				s.id'
			'\n			from' 
			'\n				${mainSchemaName}.data_package_state s' 
			'\n			where' 
			'\n				s.internal_name = ''processed'''
			'\n		)'
			'\n		, state_change_date = l_state_change_date'
			'\n	where' 
			'\n		p.id = i_data_package_id'
			'\n	;'
			'\n	io_check_date := l_state_change_date'
			'\n	;'
			'\nend'
			'\n$procedure$'
			'\n;'	
			'\ncomment on routine'
			'\n	%I.p_process_%I('
			'\n		${stagingSchemaName}.data_package.id%%type'
			'\n		, ${stagingSchemaName}.data_package.state_change_date%%type'
			'\n	) is $comment$%s$comment$'
			'\n;'
			, i_type_rec.schema_name
			, i_type_rec.internal_name
			, i_type_rec.internal_name
			-- check section
			, ${mainSchemaName}.f_indent_text(
				i_text => l_check_section 
				, i_indentation_level => 2
			)
			-- insert section
			, ${mainSchemaName}.f_indent_text(
				i_text => l_insert_proc_section
				, i_indentation_level => 3
			)
			-- delete section
			, ${mainSchemaName}.f_indent_text(
				i_text => l_delete_proc_section
				, i_indentation_level => 3
			)
			-- post processing
			, ${mainSchemaName}.f_indent_text(
				i_text => 
					concat_ws(
						E'\n;\n'		
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
							) 
							then 
								format(
									E'call'
									'\n	%I.p_after_processing_%I('
									'\n		i_data_package_id => i_data_package_id'
									'\n)' 
									, i_type_rec.schema_name 
									, i_type_rec.internal_name
								)
							end
						, format(
							E'analyze'
							'\n	%I.%I'
							, i_type_rec.schema_name
							, i_type_rec.internal_name
						) 
						, case 
							when i_type_rec.is_localization_table_generated then
								format(
									E'analyze'
									'\n	%I.%I_lc'
									, i_type_rec.schema_name
									, i_type_rec.internal_name
								) 
						end
						, (
							E'insert into'
							'\n	${stagingSchemaName}.table_stat_explicit_update_log('
							'\n		meta_type_id'
							'\n		, update_time'
							'\n		, session_context'
							'\n	)'
							'\nvalues('
							'\n	l_data_package.type_id'
							'\n	, l_state_change_date'
							'\n	, ${stagingSchemaName}.f_session_context('
							'\n		i_key => ''${session_context_key_task_name}'''
							'\n	)'
							'\n)'
						)
					)
				, i_indentation_level => 2
			)
			, i_type_rec.schema_name
			, i_type_rec.internal_name
			, i_type_rec.table_description
		)
	;
end
$$
;

comment on procedure 
	p_build_target_api(
		record
	) is 'Генерация целевого API сущности'
;
