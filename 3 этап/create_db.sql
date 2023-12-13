CREATE TYPE gender_enum AS ENUM (
    'Мужской',
    'Женский'
);

CREATE TYPE model_car AS ENUM (
    'BMW M5 Competition',
    'BMW M5 CS',
    'BMW i8',
    'BMW M8 Competition Coupe',
    'BMW M4 Competition'
);

CREATE TYPE job_title_enum AS ENUM (
    'Менеджер по обслуживанию клиентов',
    'Механик',
    'Администратор'
);

CREATE TYPE type_message_enum AS ENUM (
    'Входящее',
    'Исходящее'
);

CREATE TYPE status_order_enum AS ENUM (
    'Новое',
    'В обработке',
    'Завершено',
    'Отменено',
    'Отклонено',
    'В ожидании оплаты'
);

CREATE TABLE client (
    id serial PRIMARY KEY,
    full_name varchar(64) NOT NULL,
    birth_date date NOT NULL,
    gender gender_enum NOT NULL,
    email varchar(64) NOT NULL,
    phone_number varchar(20) NOT NULL,
    password varchar(64) NOT NULL
);

CREATE TABLE car (
    id serial PRIMARY KEY,
    year_of_release date NOT NULL,
    model model_car NOT NULL,
    colour varchar(64)
);

CREATE TABLE car_dealership (
    id serial PRIMARY KEY,
    name_car_dealership varchar(64) NOT NULL,
    email varchar(64) NOT NULL,
    phone_number varchar(20),
    passcode varchar(64) NOT NULL
);

CREATE TABLE autopart (
    id serial PRIMARY KEY,
    name_autopart varchar(64) NOT NULL,
    description_autopart text,
    model model_car NOT NULL,
    price int,
    count int 
);

CREATE TABLE employee (
    id serial PRIMARY KEY,
    full_name_employee varchar(64) NOT NULL,
    post job_title_enum NOT NULL,
    phone_number varchar(20),
    email varchar(64) NOT NULL,
    passcode varchar(64) NOT NULL,
    car_dealership_id integer,
    FOREIGN KEY (car_dealership_id) REFERENCES car_dealership(id)
);

CREATE TABLE service (
    id serial PRIMARY KEY,
    name_service varchar(64) NOT NULL,
    description_service text,
    price int,
    autopart_id integer unique,
    FOREIGN KEY (autopart_id) REFERENCES autopart(id)
);

CREATE TABLE chat (
    id serial PRIMARY KEY,
    client_id integer,
    FOREIGN KEY (client_id) REFERENCES client(id),
    employee_id integer,
    FOREIGN KEY (employee_id) REFERENCES employee(id)
);

CREATE TABLE message (
    id serial PRIMARY KEY,
    type_message type_message_enum,
    datetime_message TIMESTAMP,
    chat_id integer,
    FOREIGN KEY (chat_id) REFERENCES chat(id)
);

CREATE TABLE possession (
    id serial PRIMARY KEY,
    client_id integer,
    FOREIGN KEY (client_id) REFERENCES client(id),
    car_id integer,
    FOREIGN KEY (car_id) REFERENCES car(id)
);

CREATE TABLE my_order (
    id serial PRIMARY KEY,
    datetime_order TIMESTAMP,
    status_order status_order_enum,
    start_time TIMESTAMP,
    end_time TIMESTAMP, 
    service_id integer,
    FOREIGN KEY (service_id) REFERENCES service(id),
    employee_id integer,
    FOREIGN KEY (employee_id) REFERENCES employee(id),
    car_id integer unique,
    FOREIGN KEY (car_id) REFERENCES car(id)
);

CREATE TABLE payment (
    id serial PRIMARY KEY,
    sum_price int NOT NULL,
    datetime_payment TIMESTAMP, 
    description_payment text,   
    order_id integer unique,
    FOREIGN KEY (order_id) REFERENCES my_order(id)
);
