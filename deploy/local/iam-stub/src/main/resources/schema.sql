CREATE TABLE IF NOT EXISTS "stub_grade_manager" (
    id INT PRIMARY KEY,
    name VARCHAR(255),
    project VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS "stub_group" (
    id INT PRIMARY KEY,
    name VARCHAR(255),
    description VARCHAR(255),
    project VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS "stub_member" (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    group_id INT,
    type VARCHAR(32),
    member_id VARCHAR(255),
    expired_at BIGINT
);

CREATE TABLE IF NOT EXISTS "stub_application" (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sn VARCHAR(64),
    group_ids VARCHAR(512),
    applicant VARCHAR(255),
    status VARCHAR(32),
    callback_id INT,
    approve_result VARCHAR(16)
);

CREATE TABLE IF NOT EXISTS "stub_ticket" (
    sn VARCHAR(64) PRIMARY KEY,
    status VARCHAR(32),
    token VARCHAR(64),
    callback_id INT,
    apply_id INT
);
