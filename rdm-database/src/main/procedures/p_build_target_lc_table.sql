create or replace procedure p_build_target_lc_table(
	i_type_rec record
)
language plpgsql
as $procedure$
begin
	if i_type_rec.is_localization_table_generated = true then
		if i_type_rec.is_localization_table_exists = false then
			if i_type_rec.is_temporal = true then
				execute format('
					create table %I.%I(
						id ${type.id} not null generated by default as identity,
						master_id ${type.id} not null,
						master_version ${type.id} not null,
						attr_id ${type.id} not null,
						lang_id ${type.id} not null,
						lc_string text not null,
						is_default_value boolean not null default true,
						constraint pk_%I primary key (id),
						constraint fk_%I$master_id foreign key (master_id, master_version) references %I.%I(id, version) on delete cascade,
						constraint fk_%I$attr_id foreign key (attr_id) references ${mainSchemaName}.meta_attribute(id),
						constraint fk_%I$lang_id foreign key (lang_id) references ${mainSchemaName}.language(id)
					)'
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name				
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name
				);
				
				execute format('
					create index i_%I$master_id on %I.%I(master_id, master_version);
					create index i_%I$attr_id on %I.%I(attr_id);
					create index i_%I$lang_id on %I.%I(lang_id);
					'
					, i_type_rec.localization_table_name
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
				);
	
				execute format('
					create unique index ui_%I on %I.%I(
						master_id, master_version, attr_id, lang_id, is_default_value 
					)
					where is_default_value = true
					'
					, i_type_rec.localization_table_name
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
				);
			else
				execute format('
					create table %I.%I(
						id ${type.id} not null generated by default as identity,
						master_id ${type.id} not null,
						attr_id ${type.id} not null,
						lang_id ${type.id} not null,
						lc_string text not null,
						is_default_value boolean not null default true,
						constraint pk_%I primary key (id),
						constraint fk_%I$master_id foreign key (master_id) references %I.%I(id) on delete cascade,
						constraint fk_%I$attr_id foreign key (attr_id) references ${mainSchemaName}.meta_attribute(id),
						constraint fk_%I$lang_id foreign key (lang_id) references ${mainSchemaName}.language(id)
					)'
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name				
					, i_type_rec.schema_name
					, i_type_rec.internal_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name
				);
				
				execute format('
					create index i_%I$master_id on %I.%I(master_id);
					create index i_%I$attr_id on %I.%I(attr_id);
					create index i_%I$lang_id on %I.%I(lang_id);
					'
					, i_type_rec.localization_table_name
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
					, i_type_rec.localization_table_name
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
				);
	
				execute format('
					create unique index ui_%I on %I.%I(
						master_id, attr_id, lang_id, is_default_value 
					)
					where is_default_value = true
					'
					, i_type_rec.localization_table_name
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name
				);
			end if;	
		end if;

		if nullif(i_type_rec.table_description, i_type_rec.localization_table_description) is not null then
			execute format($$
				comment on table %I.%I is $comment$%s$comment$
				$$
				, i_type_rec.schema_name
				, i_type_rec.localization_table_name
				, i_type_rec.table_description
			);
		end if;
	
		-- ETL user role read permission
		if length('${etlUserRole}') > 0 
		then
			execute	
				format(
					'grant select on %I.%s to ${etlUserRole}'
					, i_type_rec.schema_name
					, i_type_rec.localization_table_name 
				
				);
		end if;
	
	elsif i_type_rec.is_localization_table_generated = false and i_type_rec.is_localization_table_exists = true then
		execute format('
			drop table %I.%I
			'
			, i_type_rec.schema_name
			, i_type_rec.localization_table_name
		);
	end if;
	
end
$procedure$;

comment on procedure p_build_target_lc_table(
	record
) is 'Генерация целевой таблицы локализации сущности';
