--Initializing schemas
DROP TABLE IF EXISTS Approves, Booker, Departments, Employees,
    Health_declaration, Joins, Junior, Manager, Meeting_rooms, Senior, Sessions, Updates CASCADE;
DROP FUNCTION IF EXISTS add_booker CASCADE;
DROP PROCEDURE IF EXISTS add_booker CASCADE;
DROP FUNCTION IF EXISTS add_department CASCADE;
DROP PROCEDURE IF EXISTS add_department CASCADE;
DROP FUNCTION IF EXISTS add_employee CASCADE;
DROP PROCEDURE IF EXISTS add_employee CASCADE;
DROP FUNCTION IF EXISTS add_room CASCADE;
DROP PROCEDURE IF EXISTS add_room CASCADE;
DROP FUNCTION IF EXISTS approve_meeting CASCADE;
DROP PROCEDURE IF EXISTS approve_meeting CASCADE;
DROP FUNCTION IF EXISTS book_room CASCADE;
DROP PROCEDURE IF EXISTS book_room CASCADE;
DROP FUNCTION IF EXISTS change_capacity CASCADE;
DROP PROCEDURE IF EXISTS change_capacity CASCADE;
DROP FUNCTION IF EXISTS contact_tracing CASCADE;
DROP PROCEDURE IF EXISTS contact_tracing CASCADE;
DROP FUNCTION IF EXISTS declare_health CASCADE;
DROP PROCEDURE IF EXISTS declare_health CASCADE;
DROP FUNCTION IF EXISTS join_meeting CASCADE;
DROP PROCEDURE IF EXISTS join_meeting CASCADE;
DROP FUNCTION IF EXISTS leave_meeting CASCADE;
DROP PROCEDURE IF EXISTS leave_meeting CASCADE;
DROP FUNCTION IF EXISTS non_compliance CASCADE;
DROP PROCEDURE IF EXISTS non_compliance CASCADE;
DROP FUNCTION IF EXISTS remove_department CASCADE;
DROP PROCEDURE IF EXISTS remove_department CASCADE;
DROP FUNCTION IF EXISTS remove_employee CASCADE;
DROP PROCEDURE IF EXISTS remove_employee CASCADE;
DROP FUNCTION IF EXISTS search_room CASCADE;
DROP PROCEDURE IF EXISTS search_room CASCADE;
DROP FUNCTION IF EXISTS unbook_room CASCADE;
DROP PROCEDURE IF EXISTS unbook_room CASCADE;
DROP FUNCTION IF EXISTS view_booking_report CASCADE;
DROP PROCEDURE IF EXISTS view_booking_report CASCADE;
DROP FUNCTION IF EXISTS view_future_meeting CASCADE;
DROP PROCEDURE IF EXISTS view_future_meeting CASCADE;
DROP FUNCTION IF EXISTS view_manager_report CASCADE;
DROP PROCEDURE IF EXISTS view_manager_report CASCADE;

CREATE TABLE Departments
(
    did   INTEGER PRIMARY KEY,
    dname TEXT
);

CREATE TABLE Employees
(
    eid            INTEGER PRIMARY KEY,
    did            INTEGER        NOT NULL,
    ename          TEXT           NOT NULL,
    email          TEXT UNIQUE    NOT NULL,
    home_contact   INTEGER,
    mobile_contact INTEGER UNIQUE NOT NULL,
    office_contact INTEGER UNIQUE NOT NULL,
    resigned_date  DATE DEFAULT NULL,
    traced_date    DATE DEFAULT NULL,
    FOREIGN KEY (did) REFERENCES Departments (did)
);

CREATE TABLE Meeting_Rooms
(
    room  INTEGER,
    floor INTEGER,
    rname TEXT,
    did   INTEGER NOT NULL,
    cap   INTEGER NOT NULL, -- Trigger from Updates
    PRIMARY KEY (room, floor),
    FOREIGN KEY (did) REFERENCES Departments (did) ON DELETE CASCADE
);

CREATE TABLE Junior
(
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees (eid)
);

CREATE TABLE Booker
(
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Employees (eid)
);

CREATE TABLE Senior
(
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Booker (eid) ON DELETE CASCADE
);

CREATE TABLE Manager
(
    eid INTEGER PRIMARY KEY,
    FOREIGN KEY (eid) REFERENCES Booker (eid) ON DELETE CASCADE
);

CREATE TABLE Updates
(
    date    DATE,
    new_cap INTEGER NOT NULL,
    room    INTEGER,
    floor   INTEGER,
    mid     Integer, --Manager who updates capacity
    PRIMARY KEY (date, room, floor),
    FOREIGN KEY (room, floor) REFERENCES Meeting_Rooms (room, floor) ON DELETE CASCADE,
    FOREIGN KEY (mid) REFERENCES Manager (eid) ON DELETE CASCADE
);

CREATE TABLE Sessions
(
    date  DATE,
    stime TIME,
    room  INTEGER,
    floor INTEGER,
    eid   INTEGER NOT NULL, -- Booker
    PRIMARY KEY (date, stime, room, floor),
    FOREIGN KEY (room, floor) REFERENCES Meeting_Rooms (room, floor),
    FOREIGN KEY (eid) REFERENCES Booker (eid) ON DELETE CASCADE
);

CREATE TABLE Health_Declaration
(
    date DATE,
    eid  INTEGER,
    temp NUMERIC(3, 1) CHECK (temp BETWEEN 34 AND 43 AND temp IS NOT NULL),
    PRIMARY KEY (date, eid),
    FOREIGN KEY (eid) REFERENCES Employees (eid)
);

CREATE TABLE Joins
(
    date  DATE,
    stime TIME,
    eid   INTEGER,
    room  INTEGER,
    floor INTEGER,
    PRIMARY KEY (date, stime, eid, room, floor),
    FOREIGN KEY (eid) REFERENCES Employees (eid),
    FOREIGN KEY (date, stime, room, floor) REFERENCES Sessions (date, stime, room, floor) ON DELETE CASCADE
);

CREATE TABLE Approves
(
    date  DATE,
    stime TIME,
    room  INTEGER,
    floor INTEGER,
    eid   INTEGER,
    PRIMARY KEY (date, stime, room, floor),
    FOREIGN KEY (date, stime, room, floor) REFERENCES Sessions (date, stime, room, floor) ON DELETE CASCADE,
    FOREIGN KEY (eid) REFERENCES Manager (eid) ON DELETE SET NULL
);