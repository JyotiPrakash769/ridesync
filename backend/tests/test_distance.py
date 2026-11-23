import math

import pytest

from app.services.distance_service import AlertTracker, Point, haversine_m

# ---------- haversine ----------

ONE_DEG_LAT_M = math.pi / 180 * 6_371_000  # 111,194.93 m on the R=6371 km sphere


def test_zero_distance():
    assert haversine_m(20.296, 85.824, 20.296, 85.824) == 0


def test_one_degree_of_latitude():
    assert haversine_m(0, 0, 1, 0) == pytest.approx(ONE_DEG_LAT_M, rel=1e-9)
    assert haversine_m(10, 85, 11, 85) == pytest.approx(ONE_DEG_LAT_M, rel=1e-9)


def test_longitude_shrinks_with_latitude():
    assert haversine_m(60, 0, 60, 1) == pytest.approx(ONE_DEG_LAT_M * 0.5, rel=1e-3)


def test_known_city_pairs():
    # Big Ben -> Statue of Liberty, ~5,574.8 km on a 6371 km sphere
    assert haversine_m(51.5007, -0.1246, 40.6892, -74.0445) == pytest.approx(5_574_840, rel=1e-3)
    # Bhubaneswar -> Puri, ~51 km straight line
    assert haversine_m(20.2961, 85.8245, 19.8135, 85.8312) == pytest.approx(53_670, rel=0.01)


def test_symmetric_and_short_range():
    a = (20.296, 85.824)
    b = (20.2965, 85.8245)  # ~74 m
    assert haversine_m(*a, *b) == pytest.approx(haversine_m(*b, *a))
    assert 60 < haversine_m(*a, *b) < 90


def test_antipodal_does_not_blow_up():
    assert haversine_m(0, 0, 0, 180) == pytest.approx(math.pi * 6_371_000, rel=1e-9)


# ---------- transition / debounce ----------

LEADER = ("L", "Asha")
M_PER_DEG = ONE_DEG_LAT_M


def _leader(status="online", lat=0.0):
    return Point(LEADER[0], LEADER[1], lat, 0.0, status)


def _member(dist_m, rid="m1", name="Ravi", status="online"):
    return Point(rid, name, -dist_m / M_PER_DEG, 0.0, status)


def _eval(t, members, leader=None, threshold=500):
    leader = leader or _leader()
    return t.evaluate("RIDE01", leader, [leader, *members], threshold)


def test_fires_once_on_under_to_over():
    t = AlertTracker()
    assert _eval(t, [_member(400)]) == []
    alerts = _eval(t, [_member(510)])
    assert [(a.rider_id, a.name, a.distance_m) for a in alerts] == [("m1", "Ravi", 510)]
    assert _eval(t, [_member(700)]) == []  # still over: no repeat
    assert _eval(t, [_member(900)]) == []


def test_first_sighting_over_threshold_fires():
    assert len(_eval(AlertTracker(), [_member(800)])) == 1


def test_hysteresis_prevents_flapping():
    t = AlertTracker()
    assert len(_eval(t, [_member(510)])) == 1
    assert _eval(t, [_member(490)]) == []  # under, but above 90%: still "over"
    assert _eval(t, [_member(510)]) == []  # no re-fire
    assert _eval(t, [_member(440)]) == []  # below 450: re-armed
    assert len(_eval(t, [_member(520)])) == 1  # fires again


def test_independent_per_rider():
    t = AlertTracker()
    a = _eval(t, [_member(600, "a", "A"), _member(100, "b", "B")])
    assert [x.rider_id for x in a] == ["a"]
    b = _eval(t, [_member(600, "a", "A"), _member(700, "b", "B")])
    assert [x.rider_id for x in b] == ["b"]


def test_leader_never_alerts_on_self_and_unknown_positions_skipped():
    t = AlertTracker()
    no_pos = Point("m2", "NoFix", None, None, "online")
    assert _eval(t, [no_pos]) == []


@pytest.mark.parametrize("leader_status", ["weak", "offline"])
def test_paused_while_leader_stale_then_fires_once_on_resume(leader_status):
    t = AlertTracker()
    assert len(_eval(t, [_member(600)])) == 1
    # Leader goes stale: paused, no alerts even for new offenders.
    assert _eval(t, [_member(600), _member(900, "m2", "Chen")], leader=_leader(leader_status)) == []
    # Leader back: everyone still over fires once.
    back = _eval(t, [_member(600), _member(900, "m2", "Chen")])
    assert sorted(a.rider_id for a in back) == ["m1", "m2"]
    assert _eval(t, [_member(600), _member(900, "m2", "Chen")]) == []


def test_leader_without_position_pauses():
    t = AlertTracker()
    leader = Point("L", "Asha", None, None, "online")
    assert t.evaluate("RIDE01", leader, [_member(900)], 500) == []
    assert t.evaluate("RIDE01", None, [_member(900)], 500) == []


def test_threshold_change_reset_re_evaluates():
    t = AlertTracker()
    assert len(_eval(t, [_member(600)], threshold=500)) == 1
    t.reset("RIDE01")
    assert _eval(t, [_member(600)], threshold=1000) == []
    t.reset("RIDE01")
    assert len(_eval(t, [_member(600)], threshold=300)) == 1


def test_rides_are_isolated():
    t = AlertTracker()
    leader = _leader()
    assert len(t.evaluate("A", leader, [leader, _member(600)], 500)) == 1
    assert len(t.evaluate("B", leader, [leader, _member(600)], 500)) == 1
