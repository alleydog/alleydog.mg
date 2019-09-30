-- тестовые данные
create sequence city_seq;

create table    city (
  id            bigint         default nextval('city_seq') not null,
  name          varchar(100)   not null,
  primary key(id)
);

create sequence street_seq;

create table    street (
  id            bigint         default nextval('street_seq') not null,
  city_id       bigint         not null references city(id),
  name          varchar(100)   not null,
  primary key(id)
);

create sequence address_seq;

create table    address (
  id            bigint         default nextval('address_seq') not null,
  street_id     bigint         not null references street(id),
  house         varchar(10)    not null,
  apartment     varchar(10)    not null,
  primary key(id)
);

insert into city(id, name) values (1, 'Казань');

insert into street(id, city_id, name) values (1, 1, 'Победы');
insert into street(id, city_id, name) values (2, 1, 'Победы проспект');

insert into address(id, street_id, house, apartment) values (1, 1, '10', '1');
insert into address(id, street_id, house, apartment) values (2, 2, '10', '2');
