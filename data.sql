DROP TABLE IF EXISTS GRADIENT.X
CREATE TABLE GRADIENT.X (
    [idx]   bigint          NOT NULL UNIQUE,
    [1]    decimal(19,6)   NOT NULL,
    [2]    decimal(19,6)   NOT NULL,
    [3]    decimal(19,6)   NOT NULL
)

DROP TABLE IF EXISTS GRADIENT.Y
CREATE TABLE GRADIENT.Y (
    [idx]   bigint          NOT NULL UNIQUE,
    [1]    decimal(19,6)   NOT NULL,
    [2]    decimal(19,6)   NOT NULL
)

-- TEST DATA
-- Data was generated as
-- y[0] = 3.5 * x[0] + x[1] +- uniform noise 2.5%,
-- y[1] = x[1] / 2 + x[2] +- uniform noise 2.5%

INSERT INTO GRADIENT.X VALUES
(1, 0.579, 0.686, 0.36),
(2, 0.22, 0.944, 0.773),
(3, 0.224, 0.873, 0.907),
(4, 0.412, 0.604, 0.418),
(5, 0.36, 0.559, 0.064),
(6, 0.307, 0.278, 0.459),
(7, 0.098, 0.023, 0.724),
(8, 0.147, 0.349, 0.787),
(9, 0.611, 0.764, 0.837),
(10, 0.77, 0.783, 0.477),
(11, 0.495, 0.285, 0.577),
(12, 0.523, 0.44, 0.688),
(13, 0.523, 0.016, 0.003),
(14, 0.794, 0.894, 0.774),
(15, 0.966, 0.137, 0.991),
(16, 0.245, 0.409, 0.238),
(17, 0.143, 0.797, 0.12),
(18, 0.375, 0.613, 0.439),
(19, 0.428, 0.73, 0.759),
(20, 0.173, 0.831, 0.646)

INSERT INTO GRADIENT.Y VALUES
(1, 2.742, 0.695),
(2, 1.714, 1.231),
(3, 1.67, 1.328),
(4, 2.056, 0.713),
(5, 1.802, 0.343),
(6, 1.341, 0.598),
(7, 0.369, 0.738),
(8, 0.862, 0.959),
(9, 2.916, 1.218),
(10, 3.456, 0.872),
(11, 2.043, 0.713),
(12, 2.249, 0.906),
(13, 1.847, 0.011),
(14, 3.641, 1.232),
(15, 3.524, 1.071),
(16, 1.277, 0.446),
(17, 1.285, 0.522),
(18, 1.904, 0.751),
(19, 2.241, 1.136),
(20, 1.435, 1.05)


-- VALIDATION VALUES
DROP TABLE IF EXISTS GRADIENT.Xt
CREATE TABLE GRADIENT.Xt (
    [idx]   bigint          NOT NULL UNIQUE,
    [0]    decimal(19,6)   NOT NULL,    -- bias
    [1]    decimal(19,6)   NOT NULL,
    [2]    decimal(19,6)   NOT NULL,
    [3]    decimal(19,6)   NOT NULL
)
INSERT INTO GRADIENT.Xt VALUES
(1, 1, 0.104, 0.923, 0.667),
(2, 1, 0.852, 0.852, 0.674),
(3, 1, 0.39, 0.349, 0.501),
(4, 1, 0.46, 0.444, 0.486),
(5, 1, 0.201, 0.144, 0.595)


DROP TABLE IF EXISTS GRADIENT.Yt
CREATE TABLE GRADIENT.Yt (
    [idx]   bigint          NOT NULL UNIQUE,
    [1]    decimal(19,6)   NOT NULL,
    [2]    decimal(19,6)   NOT NULL
)
INSERT INTO GRADIENT.Yt VALUES
(1, 1.283, 1.125),
(2, 3.805, 1.099),
(3, 1.707, 0.673),
(4, 2.047, 0.704),
(5, 0.853, 0.662)



-- RUN
exec [GRADIENT].[descent] 0.2, 250
-- weights overview
SELECT * FROM [GRADIENT].[W]

-- validation
EXEC [GRADIENT].[dot] 'Xt', 'W', 'V'
SELECT
    [V].[1] [pred_1],
    [V].[2] [pred_2],
    [Yt].[1] [true_1],
    [Yt].[2] [true_1]
FROM [GRADIENT].[V]
JOIN [GRADIENT].[Yt] ON [Yt].[idx] = [V].[idx]
