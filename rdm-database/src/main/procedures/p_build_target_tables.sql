create or replace procedure p_build_target_tables()
language plpgsql
as $procedure$
declare 
	l_type record;
	l_attr record;
begin
	for l_type in (
		select
			t.id,
			t.internal_name,
			${database.defaultSchemaName}.f_meta_type_dependency_level(
				i_meta_type_id => t.id
			) as dependency_level,
			case when target_table.table_name is not null then true else false end as is_table_exists,
			'pk_' || t.internal_name as pk_index_name,
			case when pk_index.indexname is not null then true else false end as is_pk_index_exists,			
			case when pk_constraint.constraint_name is not null then true else false end as is_pk_constraint_exists,
			${database.defaultSchemaName}.f_is_meta_type_has_localization(
				i_meta_type_id => t.id 
			) as is_localization_table_generated,
			t.internal_name || '_lc' as localization_table_name,
			case when lc_table.table_name is not null then true else false end as is_localization_table_exists
		from 
			${database.defaultSchemaName}.meta_type t
		left join 
			information_schema.tables target_table 
			on target_table.table_schema = '${database.defaultSchemaName}'
			and target_table.table_name = t.internal_name
			and target_table.table_type = 'BASE TABLE'
		left join pg_catalog.pg_indexes pk_index	
			on pk_index.schemaname = '${database.defaultSchemaName}'
			and pk_index.tablename = t.internal_name
			and pk_index.indexname = 'pk_' || t.internal_name
		left join 
			information_schema.table_constraints pk_constraint 
			on pk_constraint.table_schema = '${database.defaultSchemaName}'
			and pk_constraint.table_name = t.internal_name
			and pk_constraint.constraint_type = 'PRIMARY KEY'
		left join 
			information_schema.tables lc_table 
			on lc_table.table_schema = '${database.defaultSchemaName}'
			and lc_table.table_name = t.internal_name || '_lc'
			and lc_table.table_type = 'BASE TABLE'
		where 
			t.is_primitive = false
			and t.is_abstract = false
		order by 
			dependency_level desc
	) 
	loop
		if l_type.is_table_exists = false then 
			execute format('
				create table %I.%I(
					id %s not null
				)'
				, '${database.defaultSchemaName}'
				, l_type.internal_name
				, 'bigint'
			);
		end if;

		if l_type.is_pk_index_exists = false then 
			execute format('
				create unique index %I on %I.%I (
					id
				)'
				, l_type.pk_index_name 
				, '${database.defaultSchemaName}'
				, l_type.internal_name 
			);
		end if;

		if l_type.is_pk_constraint_exists = false then 
			execute format('
				alter table %I.%I
					add constraint %I primary key using index %I
				'
				, '${database.defaultSchemaName}'
				, l_type.internal_name 
				, l_type.pk_index_name 
				, l_type.pk_index_name				
			);
		end if;
		
		for l_attr in (
			select
				a.id,
				a.internal_name,
				case attr_type.internal_name
					when 's' 
						then 'varchar' ||
							case when a.length is not null 
								then '(' || a.length::text || ')' 
								else ''
							end
					when 'n' 
						then 'numeric' ||
							case when a.precision is not null 
								then '(' || a.precision::text || ', ' || coalesce(a.scale, 0)::text || ')' 
								else ''
							end
					when 'd' 
						then case when a.precision is not null 
							then 'timestamp (' || a.precision::text || ') without time zone' 
							else 'date'
						end
					when 'b' then 'boolean'
					else 'bigint'
				end as target_attr_type,
				a.ordinal_position,
				case when target_column.column_name is not null then true else false end as is_column_exists,
				case target_column.data_type
					when 'character varying' 
						then target_column.data_type ||
							case when target_column.character_maximum_length is not null
								then '(' || target_column.character_maximum_length || ')'
								else ''
							end
					when 'numeric' 
						then target_column.data_type ||
							case when target_column.numeric_precision is not null
								then '(' || target_column.numeric_precision::text || ', ' || coalesce(target_column.numeric_scale, 0)::text || ')'
								else ''
							end
					when 'timestamp without time zone' 
						then 'timestamp (' || coalesce(target_column.datetime_precision, 6)::text || ') without time zone'
					else 
						target_column.data_type
				end as column_data_type,
				case 
					when attr_type.is_abstract = true and a.is_reflective_link = true 
						then l_type.internal_name
					else
						attr_type.internal_name
				end as attr_type_name,
				case when attr_type.is_primitive = false then true else false end as is_fk_constraint_added,
				'fk_' || l_type.internal_name || '$' || a.internal_name as fk_constraint_name,
				case when fk_constraint.constraint_name is not null then true else false end as is_fk_constraint_exists,
				case when fk_index.indexname is not null then true else false end as is_fk_index_exists,			
				a.is_non_nullable,
				case when target_column.is_nullable = 'NO' then true else false end as is_notnull_constraint_exists,
				a.is_unique,
				'uc_' || l_type.internal_name || '$' || a.internal_name as unique_constraint_name,
				case when u_constraint.constraint_name is not null then true else false end as is_unique_constraint_exists,
				a.default_value,
				target_column.column_default
			from 
				${database.defaultSchemaName}.v_meta_attribute a
			join 
				${database.defaultSchemaName}.meta_type attr_type
				on attr_type.id = a.attr_type_id				
			left join 
				information_schema.columns target_column
				on target_column.table_schema = '${database.defaultSchemaName}'
				and target_column.table_name = l_type.internal_name
				and target_column.column_name = a.internal_name
			left join 
				information_schema.table_constraints fk_constraint 
				on fk_constraint.table_schema = '${database.defaultSchemaName}'
				and fk_constraint.table_name = l_type.internal_name
				and fk_constraint.constraint_name = 'fk_' || l_type.internal_name || '$' || a.internal_name
				and fk_constraint.constraint_type = 'FOREIGN KEY'
			left join pg_catalog.pg_indexes fk_index	
				on fk_index.schemaname = '${database.defaultSchemaName}'
				and fk_index.tablename = l_type.internal_name
				and fk_index.indexname = 'fk_' || l_type.internal_name || '$' || a.internal_name
			left join 
				information_schema.table_constraints u_constraint 
				on u_constraint.table_schema = '${database.defaultSchemaName}'
				and u_constraint.table_name = l_type.internal_name
				and u_constraint.constraint_name = 'uc_' || l_type.internal_name || '$' || a.internal_name
				and u_constraint.constraint_type = 'UNIQUE'
			where 
				a.meta_type_id = l_type.id
				and a.is_localisable = false
			order by 
				ordinal_position asc nulls last, 
				id asc 
		) 
		loop
			if l_attr.is_column_exists = false then 
				execute format('
					alter table %I.%I
						add column %I %s %s null
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.internal_name 
					, l_attr.target_attr_type				
					, case when l_attr.is_non_nullable = true then 'not ' else '' end
				);
			else
				if l_attr.target_attr_type <> l_attr.column_data_type then 
					execute format('
						alter table %I.%I
							alter column %I set data type %s
						'
						, '${database.defaultSchemaName}'
						, l_type.internal_name 
						, l_attr.internal_name 
						, l_attr.target_attr_type
					);
				end if;
			end if;

			if l_attr.is_fk_constraint_added = true and l_attr.is_fk_index_exists = false then
				execute format('
					create index %I on %I.%I (
						%s
					)'
					, l_attr.fk_constraint_name
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.internal_name
				);
			elsif l_attr.is_fk_constraint_added = false and l_attr.is_fk_index_exists = true then
				execute format('
					drop index %I.%I
					'
					, '${database.defaultSchemaName}'
					, l_attr.fk_constraint_name
				);
			end if;

			if l_attr.is_fk_constraint_added = true and l_attr.is_fk_constraint_exists = false then
				execute format('
					alter table %I.%I
						add constraint %I foreign key (%s) references %I.%I(id) 
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.fk_constraint_name
					, l_attr.internal_name
					, '${database.defaultSchemaName}'
					, l_type.attr_type_name 
				);
			elsif l_attr.is_fk_constraint_added = false and l_attr.is_fk_constraint_exists = true then
				execute format('
					alter table %I.%I
						drop constraint %I
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.fk_constraint_name
				);
			end if;
			
			if l_attr.is_non_nullable = true and l_attr.is_notnull_constraint_exists = false then
				execute format('
					alter table %I.%I
						alter column %I set not null
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.internal_name 
				);
			elsif l_attr.is_non_nullable = false and l_attr.is_notnull_constraint_exists = true then
				execute format('
					alter table %I.%I
						alter column %I drop not null
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.internal_name 
				);
			end if;

			if l_attr.is_unique = true and l_attr.is_unique_constraint_exists = false then
				execute format('
					alter table %I.%I
						add constraint %I unique (%s)
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.unique_constraint_name
					, l_attr.internal_name
				);
			elsif l_attr.is_unique = false and l_attr.is_unique_constraint_exists = true then
				execute format('
					alter table %I.%I
						drop constraint %I
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.unique_constraint_name
				);
			end if;

			if l_attr.default_value is not null and l_attr.default_value <> coalesce(l_attr.column_default, '') then
				execute format('
					alter table %I.%I
						alter column %I set default %s
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.internal_name 
					, l_attr.default_value
				);
			elsif l_attr.default_value is null and l_attr.column_default is not null then
				execute format('
					alter table %I.%I
						alter column %I drop default
					'
					, '${database.defaultSchemaName}'
					, l_type.internal_name 
					, l_attr.internal_name 
				);
			end if;

		end loop;
	
		if l_type.is_localization_table_generated = true and l_type.is_localization_table_exists = false then
			execute format('
				create table %I.%I(
					id integer not null generated by default as identity,
					type_id integer not null,
					attr_id integer not null,
					lang_id integer not null,
					lc_string varchar(4000) not null,
					is_default_value boolean not null default true,
					constraint pk_%I primary key (id),
					constraint fk_%I$type_id foreign key (type_id) references %I.%I(id),
					constraint fk_%I$attr_id foreign key (attr_id) references %I.meta_attribute(id),
					constraint fk_%I$lang_id foreign key (lang_id) references %I.language(id)
				)'
				, '${database.defaultSchemaName}'
				, l_type.localization_table_name
				, l_type.localization_table_name
				, l_type.localization_table_name				
				, '${database.defaultSchemaName}'
				, l_type.internal_name
				, l_type.localization_table_name
				, '${database.defaultSchemaName}'
				, l_type.localization_table_name
				, '${database.defaultSchemaName}'				
			);
			
			execute format('
				create index i_%I$type_id on %I.%I(type_id);
				create index i_%I$attr_id on %I.%I(attr_id);
				create index i_%I$lang_id on %I.%I(lang_id);
				'
				, l_type.localization_table_name
				, '${database.defaultSchemaName}'
				, l_type.localization_table_name
				, l_type.localization_table_name
				, '${database.defaultSchemaName}'
				, l_type.localization_table_name
				, l_type.localization_table_name
				, '${database.defaultSchemaName}'
				, l_type.localization_table_name
			);

			execute format('
				create unique index ui_%I on %I.%I(
					type_id, attr_id, lang_id, is_default_value 
				)
				where is_default_value = true
				'
				, l_type.localization_table_name
				, '${database.defaultSchemaName}'
				, l_type.localization_table_name
			);
			
		elsif l_type.is_localization_table_generated = false and l_type.is_localization_table_exists = true then
			execute format('
				drop table %I.%I
				'
				, ${database.defaultSchemaName}
				, l_type.localization_table_name
			);
		end if;
		
	end loop;
	
end
$procedure$;			
