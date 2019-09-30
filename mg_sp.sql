create or replace
    function mg_get_pk_column(p_schema character varying, p_table character varying) returns character varying
    language plpgsql as
$function$
declare
    l_pk text;
    l_cn int;
begin
    select max(f.name), count(*) as name
    into
        l_pk,
        l_cn
    from (select unnest(a.conkey) as nn
          from pg_constraint a,
               pg_class b,
               pg_namespace ns
          where b.oid = a.conrelid
            and a.contype = 'p'
            and a.connamespace = ns.oid
            and ns.nspname = p_schema
            and b.relname = lower(p_table)) c,
         (select d.attname as name, d.attnum as nn
          from pg_attribute d,
               pg_class e,
               pg_namespace ns
          where e.oid = d.attrelid
            and ns.nspname = p_schema
            and e.relnamespace = ns.oid
            and e.relname = lower(p_table)) f
    where f.nn = c.nn;
    if l_cn <> 1 then
        raise notice 'Schema: %', p_schema;
        raise exception 'Can''t support composite PK';
    end if;
    return l_pk;
end;
$function$;

create or replace
    function mg_add_dict(p_schema character varying,
                             p_table character varying) returns void
    language plpgsql as
$function$
declare
    l_pk  text;
    l_sql text;
begin
    l_pk := mg_get_pk_column(p_schema,
                             p_table);

    perform 1
    from mg_table
    where table_name = lower(p_table);

    if not found then
        l_sql := 'create table mg_' || lower(p_table) || ' ' || 'as select * from ' || lower(p_table) || ' limit 0';

        execute l_sql;

        l_sql := 'alter table mg_' || lower(p_table) || ' ' || 'add primary key(' || l_pk || ')';

        execute l_sql;

        insert
        into mg_table(table_name,
                      pk_name)
        values (lower(p_table),
                l_pk);
    end if;
end;

$function$;

create or replace
    function mg_merge(p_schema character varying,
                          p_table character varying,
                          p_old character varying,
                          p_new character varying) returns void
    language plpgsql as
$function$
declare
    l_action int;
    l_pk     text;
    l_sql    text;
    tabs     record;
begin
    perform mg_add_dict(p_schema,
                        p_table);

    select pk_name
    into
        l_pk
    from mg_table
    where table_name = lower(p_table);

    l_action := nextval('mg_action_seq');

    insert
    into mg_action(id,
                   table_name,
                   old_id,
                   new_id)
    values (l_action,
            p_table,
            p_old,
            p_new);

    l_sql := 'insert into mg_' || lower(p_table) || ' ' || 'select * from ' || lower(p_table) || ' ' || 'where ' ||
             l_pk || ' = ''' || p_old || '''';

    execute l_sql;

    for tabs in
        select b.relname as table_name,
               d.attname as column_name
        from pg_constraint a,
             pg_class b,
             pg_class c,
             pg_attribute d
        where a.contype = 'f'
          and b.oid = a.conrelid
          and c.oid = a.confrelid
          and c.relname = lower(p_table)
          and d.attrelid = b.oid
          and a.conkey[1] = d.attnum
        loop
            l_sql := 'insert into mg_action_detail(action_id, table_name, column_name, obj_id, pk_name) ' ||
                     'select ' || l_action || ', ''' || tabs.table_name || ''', ''' || tabs.column_name || ''', id, ' ||
                     '''' || mg_get_pk_column(p_schema,
                                              tabs.table_name::varchar) || ''' ' || 'from ' || lower(tabs.table_name) ||
                     ' ' || 'where ' || lower(tabs.column_name) || ' = ''' || p_old || '''';

            execute l_sql;

            l_sql := 'update ' || lower(tabs.table_name) || ' ' || 'set ' || lower(tabs.column_name) || ' = ''' ||
                     p_new || ''' ' || 'where ' || lower(tabs.column_name) || ' = ''' || p_old || '''';

            execute l_sql;
        end loop;

    l_sql := 'delete from ' || lower(p_table) || ' where ' || l_pk || ' = ''' || p_old || '''';

    execute l_sql;
end;

$function$;

create or replace
    function mg_merge(p_schema character varying,
                          p_table character varying,
                          p_old bigint,
                          p_new bigint) returns void
    language plpgsql as
$function$
declare
begin
    perform mg_merge(p_schema,
                     p_table,
                     p_old::varchar,
                     p_new::varchar);
end;

$function$;

create or replace
    function mg_undo() returns void
    language plpgsql as
$function$
declare
    l_action int;
    l_old    varchar(50);
    l_table  text;
    l_sql    text;
    tabs     record;
begin
    select max(id)
    into
        l_action
    from mg_action;

    if l_action is null then
        raise exception 'can''t undo';
    end if;

    select table_name,
           old_id
    into
        l_table,
        l_old
    from mg_action
    where id = l_action;

    l_sql := 'insert into ' || l_table || ' ' || 'select * from mg_' || l_table || ' ' || 'where id = ''' || l_old ||
             '''';

    execute l_sql;

    for tabs in
        select table_name,
               pk_name,
               column_name
        from mg_action_detail
        where action_id = l_action
        group by table_name,
                 pk_name,
                 column_name
        loop
            l_sql := 'update ' || tabs.table_name || ' ' || 'set ' || tabs.column_name || ' = ''' || l_old || ''' ' ||
                     'where '''' || ' || tabs.pk_name || ' in (' || 'select '''' || obj_id from mg_action_detail ' ||
                     'where table_name = ''' || tabs.table_name || ''' ' || 'and action_id = ' || l_action || ') ';

            execute l_sql;
        end loop;

    l_sql := 'delete from mg_' || l_table || ' where id = ''' || l_old || '''';

    execute l_sql;

    delete
    from mg_action_detail
    where action_id = l_action;

    delete
    from mg_action
    where id = l_action;
end;

$function$;
