#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Class to implement transparent DB access"""

class DBObjectError(Exception):
    """Our own Exception Class"""
    def __init__(self, value):
        super(DBObjectError, self).__init__()
        self.value = value
    def __str__(self):
        """convert value to string"""
        return repr(self.value)


class DBTable(object):
    """Class to implement transparent DB access"""
    def __init__(self, table_name, db, params=None):
        self.__db = db
        self.__name = table_name
        self.__schema = {}
        self.__refs = {}
        self.__rev_refs = []
        self.__virtual = {}
        self.__initialized = 0
        if params == None:
            params = {}
        if 'create_table' in params:
            self.__create_table = params['create_table']
        else:
            self.__create_table = 1
        self.__primary_key = None
        self._add_field('_id', ('INTEGER', 'PRIMARY KEY'))

    def name(self):
        """returns table name"""
        return self.__name
    
    def primary_key(self):
        """returns primary key"""
        return self.__primary_key

    def _db_update(self,  u_sql,  t_data = ()):
        """does db update and commits changes"""
        if not self.__initialized:
            self._init_table()
        return self.__db._db_update(u_sql, t_data)

    def _db_select(self,  u_sql,  t_data = ()):
        """does db update and commits changes"""
        if not self.__initialized:
            self._init_table()
        return self.__db._db_select(u_sql, t_data)

    def __tuple(self, param):
        """converts given parameter to tuple"""
        if type(param).__name__ == 'tuple':
            return param
        if hasattr(param, '__iter__'):
            return tuple(param)
        return (param,)

    def _add_field(self, u_name, types):
        """adds a field of given type to db"""
        if self.__initialized:
            raise DBObjectError(
                "Table '" + self.name() + "' is already initialized."
            )
        types = [_.upper() for _ in self.__tuple(types)]
        if 'PRIMARY KEY' in types:
            if self.__primary_key != None:
                if self.__primary_key != '_id':
                    raise DBObjectError(
                        "You hav already defined a PRIMARY KEY named '"
                        + self.__primary_key + "'."
                    )
                del self.__schema[self.__primary_key]
            self.__primary_key = u_name.lower()
        u_type = " ".join(types)
        if self.has_field(u_name):
            raise DBObjectError(
                "Field '" + u_name + "' already in table '" + self.name() + "'."
            )
        self.__schema[u_name.lower()] = u_type

    def _add_mandatory_field(self, u_name, types):
        """adds a mandatory field to db"""
        types = tuple(_.upper() for _ in self.__tuple(types))
        if not 'NOT NULL' in types:
            types = types + ('NOT NULL',)
        self._add_field(u_name, types)

    def _add_ref(
        self, u_name, ref, ref_field = None,
        types=(), virtual = None, ref_virtual = None
    ):
        """adds a reference field to db
        'virtual' may be a virtual column name in this table for references
            object
        'ref_virtual' may be a virtual column name in refrenced table
        """
        if not isinstance(ref, DBTable):
            raise DBObjectError(
                "Instance '" + type(ref).__name__
                + "' is not a sub class of DBObject."
            )
        if ref_field == None:
            ref_field = ref.__primary_key
        ref_field = ref_field.lower()
        if not ref.has_real_field(ref_field):
            raise DBObjectError(
                "Table '" + ref.name()
                + "' has no field '" + ref_field + "'."
            )
        types = ('INTEGER',) + self.__tuple(types)
        self._add_field(u_name, types)
        self.__refs[u_name.lower()] = (ref, ref_field)
        ref.__rev_refs.append({
            'field': ref_field,
            'ref': self,
            'ref_field': u_name,
        })
        if virtual != None:
            self._add_virtual(virtual, u_name, ref, ref_field, single = 1)
        if ref_virtual != None:
            ref._add_virtual(ref_virtual, ref_field, self, u_name)

    def _add_mandatory_ref(
        self, u_name, ref, ref_field = None,
        types = (), virtual = None, ref_virtual = None
    ):
        """adds a mandatory reference"""
        types = ('NOT NULL',) + self.__tuple(types)
        self._add_ref(u_name, ref, ref_field, types, virtual, ref_virtual)

    def _add_virtual(
        self, name, field, ref, ref_field, single = None, next_field = None
    ):
        """adds a virtual column
        name: name of the virtual field
        field: matching field in this table
        ref: another table
        ref_field: matching field in other table
        single: if Ture only one object will be fetched
        next_field: only return this field of found objects
        """
        if self.has_field(name):
            raise DBObjectError(
                "Field '" + name + "' already in table '" + self.name() + "'."
            )
        if not self.has_real_field(field):
            raise DBObjectError(
                "Field '" + field + "' not in table '" + self.name() + "'."
            )
        if not ref.has_field(ref_field):
            raise DBObjectError(
                "Field '" + ref_field + "' not in table '" + ref.name() + "'."
            )
        if next_field != None and not ref.has_field(next_field):
            raise DBObjectError(
                "Field '" + next_field + "' not in table '" + ref.name() + "'."
            )
        self.__virtual[name] = {
            'field': field,
            'ref': ref,
            'ref_field': ref_field,
            'single': single,
            'next_field': next_field,
        }

    def has_field(self, name):
        """returns true if table contains column"""
        return self.has_real_field(name) or self.has_virtual_field(name)

    def has_virtual_field(self, name):
        """returns true if table has virtual column"""
        t_name = self.correct_field_name(name).split('.')
        if t_name[0] == self.name():
            return t_name[1] in self.__virtual
        return False

    def has_real_field(self, name):
        """returns true if table has real column"""
        t_name = self.correct_field_name(name).split('.')
        if t_name[0] == self.name():
            return t_name[1] in self.__schema
        return False

    def _init_table(self):
        """initialize table"""
        self.__initialized = 1
        if not self.__create_table:
            return
        u_query = 'CREATE TABLE IF NOT EXISTS ' + self.__name + " (\n\t"
        u_query += ",\n\t".join(
            [
                " ".join(
                    (_, self.__schema[_])
                ) for _ in sorted(self.__schema)
            ]
        )
        u_query += "\n)"
        self._db_update(u_query)
    
    def correct_field_name(self, field, set_tables = None):
        """makes every field name preceded by table name.
        adds table name to set_tables (if not None)
        """
        t_field = field.split('.', 1)
        if len(t_field) < 2:
            t_field = (self.name(), t_field[0])
        if set_tables != None:
            set_tables .add(t_field[0])
        return '.'.join(t_field)

    def __build_where_clause(self, where):
        """build where clause"""
        if where == None:
            return ('', set(), ())
        # set of all referenced tables
        set_tables = set()
        where_fields = where.keys()
        # operators for where expressions
        where_op = {}
        # values for where expressions
        where_val = {}
        # wildcards or table fields for where expressions
        # ('?' or reference to other field)
        where_wild = {}
        # fill previous defined where-dicts
        # where values may be of different types: scalar, list or dict
        for key, value in where.iteritems():
            where_wild[key] = '?'
            if hasattr(value, '__iter__'):
                if type(value).__name__ == 'dict':
                    where_op[key] = value.setdefault('op', '=')
                    where_val[key] = value.setdefault('value', None)
                    if 'field' in value:
                        where_wild[key] = self.correct_field_name(
                            value['field'],
                            set_tables,
                        )
                    continue
                if len(value)  == 2:
                    where_op[key] = value[0]
                    where_val[key] = value[1]
                    continue
                where_op[key] = '='
                where_val[key] = value[0]
                continue
            where_op[key] = '='
            where_val[key] = value

        u_where = ""
        if where_fields:
            u_where = " WHERE " + " AND ".join(
                [
                    " ".join((
                        self.correct_field_name(_, set_tables),
                        where_op[_],
                        where_wild[_],
                    ))
                    for _ in where_fields
                ]
            )

        values = tuple(
            where_val[_] for _ in where_fields if where_wild[_] == '?'
        )
        return (u_where, set_tables, values)


    def __do_select(self, fields, where=None):
        """executes select on given fields with specified where construct"""

        u_where, set_tables, values = self.__build_where_clause(where)

        u_query = "SELECT " + ", ".join(
            [self.correct_field_name(_, set_tables) for _ in fields]
        )

        u_query += " FROM " + ", ".join([_ for _ in set_tables]) + u_where

        return self._db_select(
            u_query,
            values,
        )
    
    def __map_virtuals(self, where):
        """map virtual where fields to real fields"""
        result = {}
        for key, value in where.iteritems():
            if self.has_real_field(key):
                result[key] = value
                continue
            virtual = self.__virtual[key]
            ref_table = virtual['ref'].name()
            result[virtual['field']] = {
                'op': '=',
                'field': '.'.join((ref_table, virtual['ref_field'])),
            }
            if virtual['next_field']:
                sub_where = virtual['ref'].__map_virtuals(
                    {'.'.join((ref_table, virtual['next_field'])): value}
                )
                for key2, value2 in sub_where.iteritems():
                    result[key2] = value2
            
        return result
    
    def get(self, where=None, col=None):
        """get generator for selected DBObjects"""
        if not where:
            where = {}
        if [_ for _ in where.keys() if not self.has_field(_)]:
            raise DBObjectError(
                "At least one field in '"
                + "', '".join(where.keys()) + "' is not in Table '"
                + self.name() + "'."
            )
        fields = self.__schema.keys()
        result = self.__do_select(fields, where=self.__map_virtuals(where))

        if result == None:
            return
        
        for row in result:
            dbo = DBObject(self)
            dbo._assign(dict(zip(fields, row)))
            if col == None:
                yield dbo
            else:
                yield dbo.get(col)

    def get_single(self, where=None, col=None):
        """returns first matching dbobject"""
        for result in self.get(where=where, col=col):
            return result
        return None

    def _virtual_factory(self, dbo):
        """build hash table of functions to retrieve virtual values"""

        def build_virtual(settings):
            """builds virtual function"""
            if settings['single']:
                fetch = settings['ref'].get_single
            else:
                fetch = settings['ref'].get
            return lambda: fetch(
                where={settings['ref_field']: dbo.get(settings['field'])},
                col = settings['next_field'],
            )

        result = {}
        for name in self.__virtual:
            result[name] = build_virtual(self.__virtual[name])
        return result
    
    def _update(self, dbo):
        """updates dbo in database"""
        data = dbo.data()
        primary_value = dbo.primary_value()
        if primary_value == None:
            raise DBObjectError("Primary key ist not set!")
        l_fields = data.keys()
        u_sql = "UPDATE " + self.name() + " SET " + ", ".join(
            [_ + "=?" for _ in l_fields]
        ) + " WHERE " + self.__primary_key + "=?"
        result = self._db_update(
            u_sql,
            tuple(data[_] for _ in l_fields) + (primary_value,)
        )
        if result == None:
            return None
        dbo._set_primary_value()
        return result.rowcount

    def _insert(self, dbo):
        """inserts new dbo into database"""
        data = dbo.data()
        l_fields = data.keys()
        u_sql = "INSERT INTO " + self.name() + " (" + ", ".join(
            [_ for _ in l_fields]
        ) + ") VALUES (" + ", ".join(["?" for _ in l_fields])+ ")"
        result = self._db_update(u_sql, tuple(data[_] for _ in l_fields))
        if result == None:
            return None
        # now get the whole dataset from table (with primary key)
        fields = self.__schema.keys()
        result = self.__do_select(
            fields,
            where={'_ROWID_': ['=', result.lastrowid]},
        )
        if result == None:
            return None
        for row in result:
            dbo._assign(dict(zip(fields, row)))
            return 1
        return None
        
    def _set_virtual(self, dbo, field, dbo_foreign):
        """sets real field of dbo as specified by virtual"""
        if not self.has_virtual_field(field):
            raise DBObjectError(
                "Virtual field '" + field + "' does not exist in table '"
                + self.name() + "'."
            )
        virtual = self.__virtual[field]
        if dbo_foreign == None:
    	    dbo.set(virtual['field'], None)
    	    return
        if virtual['ref'] != dbo_foreign._get_table():
            raise DBObjectError(
                "Virtual field '" + field + "' references table '"
                + virtual['ref'].name() + "', but table '"
                + dbo_foreign._get_table().name() + "' was given."
            )
        if not virtual['single']:
            raise DBObjectError(
                "Virtual field '" + field + "' is not declared as 'single'."
            )
        dbo.set(virtual['field'], dbo_foreign.get(virtual['ref_field']))

    def _get_virtual(self, field, where):
        """gets virtual value's object by where clause"""
        if not self.has_virtual_field(field):
            raise DBObjectError(
                "Virtual field '" + field + "' does not exist in table '"
                + self.name() + "'."
            )
        virtual = self.__virtual[field]
        if not virtual['single']:
            raise DBObjectError(
                "Virtual field '" + field + "' is not declared as 'single'."
            )
        return virtual['ref'].get_single(where)

    def _new_virtual(self, field, data=None):
        """creates new virtual value for object with given data"""
        if not self.has_virtual_field(field):
            raise DBObjectError(
                "Virtual field '" + field + "' does not exist in table '"
                + self.name() + "'."
            )
        virtual = self.__virtual[field]
        if not virtual['single']:
            raise DBObjectError(
                "Virtual field '" + field + "' is not declared as 'single'."
            )
        dbo = DBObject(virtual['ref'])
        if data:
            for name in data:
                dbo.set(name, data[name])
        dbo.flush()
        return dbo

    def __check_xref(self, field):
        """returns virtual objects and raises exception on error"""
        if not self.has_virtual_field(field):
            raise DBObjectError(
                "Virtual field '" + field + "' does not exist in table '"
                + self.name() + "'."
            )
        virtual = self.__virtual[field]
        if virtual['single']:
            raise DBObjectError(
                "Virtual field '" + field + "' is declared as 'single'."
            )
        if not virtual['next_field']:
            raise DBObjectError(
                "There is no defined next_field."
            )
        if not virtual['ref'].has_field(virtual['next_field']):
            raise DBObjectError(
                "Field '" + virtual['next_field'] + "' does not exist in table '"
                + virtual['ref'].name() + "'."
            )
        next_virtual = virtual['ref'].__virtual[virtual['next_field']]
        return (virtual, next_virtual)

    def set_xref(self, field, dbo, data={}, x_data={}):
        """removes xref with given datas"""
        virtual, next_virtual = self.__check_xref(field)

        dbo_value = dbo.get(virtual['field'])
        if not dbo_value:
            dbo.flush()
            dbo_value = dbo.get(virtual['field'])
        xref = DBObject(virtual['ref'])
        xref.set(virtual['ref_field'], dbo_value)
        xref.ref_or_create(virtual['next_field'], data)
        for key in x_data:
            xref.set(key, x_data[key])
        xref.flush()

    def remove_xref(self, field, dbo, dbo_foreign):
        """removes xref with given datas"""
        virtual, next_virtual = self.__check_xref(field)
        virtual['ref'].__delete_where(
            where={
                virtual['ref_field']: dbo.get(virtual['field']),
                next_virtual['field']: dbo_foreign.get(next_virtual['ref_field']),
            }
        )

    def __delete_where(self, where):
        """deletes all entries specified by where"""
        where, set_tables, values = self.__build_where_clause(where)
        u_sql = "DELETE FROM " + self.name() + where
        return self._db_update(u_sql, values)

    def delete(self, dbo, cleanup=False):
        """deletes dbo from table
        cleanup: if True, deletes all records referencing this dbo
        """
        result = self.__delete_where(
            where={
                self.__primary_key: dbo.primary_value(),
            }
        )
        if result == None:
            return None
        if cleanup:
            for ref in self.__rev_refs:
                for del_dbo in ref['ref'].get(
                    where={
                        ref['ref_field']: dbo.get(ref['field']),
                    }
                ):
                    del_dbo.delete(cleanup=cleanup)
        return result.rowcount

class DBObject(object):
    """Class to implement transparent DB access"""
    def __init__(self, table, db = None):
        self.__data = {}
        self.__primary_value = None
        self.__is_new = True
        self.__is_changed = False
        if type(table).__name__ == 'str':
            self.__table = DBTable(table, db)
        else:
            self.__table = table
        self.__virtual = self.__table._virtual_factory(self)
    
    def _assign(self, row):
        """assign current object with result row"""
        self.__data = {}
        for key in row.keys():
            self.__data[key] = row[key]
        self._set_primary_value()
        self.__virtual = self.__table._virtual_factory(self)
        self.__is_new = False
        self.__is_changed = False
    
    def _set_primary_value(self):
        """sets primray value after update"""
        self.__primary_value = self.__data[self.__table.primary_key()]

    def get(self, name):
        """get specified property"""
        name = name.lower()
        if not self.__table.has_field(name):
            raise DBObjectError(
                "Table '" + self.__table.name() + "' does not contain field '" + name + "'."
            )

        if not self.__data:
            raise DBObjectError("No data in " + self.__class__.__name__)
        if self.__table.has_real_field(name):
            if name in self.__data:
                return self.__data[name]
        if self.__table.has_virtual_field(name):
            if name in self.__virtual:
                if type(self.__virtual[name]).__name__ == 'function':
                    return self.__virtual[name]()
                return self.__virtual[name]
    
    def data(self):
        """returns a copy of our data"""
        return dict(self.__data)
    
    def primary_value(self):
        """returns orignial value of primary key"""
        return self.__primary_value
        
    def _get_table(self):
        """returns our table"""
        return self.__table
    
    def set(self, name, value):
        """sets given field with value"""
        name = name.lower()
        if not self.__table.has_field(name):
            raise DBObjectError(
                "Table '" + self.__table.name() + "' does not contain field '" + name + "'."
            )
        if self.__table.has_real_field(name):
            if (name in self.__data and self.__data[name] == value):
                return
            self.__data[name] = value
        else:
            self.__table._set_virtual(self, name, value)
        self.__is_changed = True
    
    def ref_or_create(self, name, where):
        """reference another table, create entry if needed"""
        if not self.__table.has_virtual_field(name):
            raise DBObjectError(
                "Table '" + self.__table.name() + "' does not contain virtual field '" + name + "'."
            )
        # return if no where value exists
        b_empty = True
        for key in where:
            if where[key] != None:
                b_empty = False
                break
        if b_empty:
            self.__table._set_virtual(self, name, None)
            return
        db_ref = self.__table._get_virtual(name, where)
        if not db_ref:
            db_ref = self.__table._new_virtual(name, where)
        self.set(name, db_ref)
    
    def xref(self, name, wheres, x_datas=[]):
        """create and clean up x-references to another table, create entries if needed"""
        if not self.__table.has_virtual_field(name):
            raise DBObjectError(
                "Table '" + self.__table.name() + "' does not contain virtual field '" + name + "'."
            )
        old_refs = []
        for ref in self.get(name):
            b_found = False
            for i in range(len(wheres)):
                if wheres[i] == None:
                    continue
                b_found = True
                for field in wheres[i]:
                    if ref.get(field) != wheres[i][field]:
                        b_found = False
                        break
                if b_found:
                    wheres[i] = None
#                    if i < len(x_datas) and x_datas[i]:
#                        x_data = x_datas[i]
#                        for x_data_key in x_data:
#                            ref.set(x_data_key, x_data[x_data_key])
#                        ref.flush()
                    break
            if not b_found:
                old_refs.append(ref)
        for i in range(len(wheres)):
            if wheres[i] == None:
                continue
            x_data = {}
            if i < len(x_datas):
                x_data = x_datas[i]
            self.__table.set_xref(name, self, wheres[i], x_data)
        for ref in old_refs:
            self.__table.remove_xref(name, self, ref)
    
    def flush(self):
        """flushes changes to table"""
        if not self.__is_changed:
            return 1
        if self.__is_new:
            return self.__table._insert(self)
        self.__is_changed = False
        return self.__table._update(self)
        
    def delete(self, cleanup=False):
        """removes current dbo
        cleanup: if true removes all references
        """
        if self.__is_new:
            return True

        self.__table.delete(self, cleanup=cleanup)

        self.__is_new = True
        self.__data = {}
        self.__primary_value = None
        self.__virtual = {}
        self.__is_changed = False
    
    
