-- BagTrace database schema and sample data (MySQL 8).
-- Safe to run more than once.

CREATE DATABASE IF NOT EXISTS bagtrace;
USE bagtrace;

CREATE TABLE IF NOT EXISTS bags (
  tag          CHAR(10)     NOT NULL PRIMARY KEY COMMENT '10-digit IATA licence plate',
  flight       VARCHAR(8)   NOT NULL,
  flight_date  CHAR(5)      NOT NULL COMMENT 'DDMMM, e.g. 18OCT',
  origin       CHAR(3)      NOT NULL,
  destination  CHAR(3)      NOT NULL,
  passenger    VARCHAR(64)  NULL,
  weight_kg    SMALLINT     NULL,
  status       VARCHAR(16)  NOT NULL DEFAULT 'CHECKED_IN',
  updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_flight (flight, flight_date),
  INDEX idx_status (status)
);

CREATE TABLE IF NOT EXISTS bag_events (
  id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  tag         CHAR(10)     NOT NULL,
  event       VARCHAR(24)  NOT NULL,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_tag (tag)
);

-- Sample bags so the dashboard is not empty on first launch.
INSERT IGNORE INTO bags (tag, flight, flight_date, origin, destination, passenger, weight_kg, status) VALUES
  ('0081123456', 'QF401', '18OCT', 'MEL', 'SYD', 'SMITH JOHN',   18, 'LOADED'),
  ('0081123457', 'QF401', '18OCT', 'MEL', 'SYD', 'SMITH JOHN',   13, 'SCREENED'),
  ('0176543210', 'EK525', '18OCT', 'HYD', 'DXB', 'REDDY ANIL',   23, 'CHECKED_IN'),
  ('0098765432', 'AI101', '18OCT', 'DEL', 'JFK', 'RAO PRIYA',    22, 'OFFLOADED'),
  ('0123400001', 'NZ102', '18OCT', 'AKL', 'SYD', 'WILSON EMMA',  20, 'ARRIVED'),
  ('0176543211', 'EK525', '18OCT', 'HYD', 'DXB', 'REDDY KAVYA',  21, 'LOADED');

INSERT INTO bag_events (tag, event)
SELECT b.tag, 'BSM_ADD' FROM bags b
WHERE NOT EXISTS (SELECT 1 FROM bag_events e WHERE e.tag = b.tag);
