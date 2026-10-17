import pytest

from bsm import BSMError, parse_bsm

SAMPLE = """BSM
.V/1LMEL
.F/QF401/18OCT/SYD/Y
.N/0081123456002
.W/K/2/31
.P/1SMITH/JOHN
ENDBSM"""


def test_parses_core_elements():
    msg = parse_bsm(SAMPLE)
    assert msg.action == "ADD"
    assert msg.airport == "MEL"
    assert (msg.flight, msg.flight_date, msg.destination, msg.travel_class) == ("QF401", "18OCT", "SYD", "Y")
    assert msg.passenger == "SMITH JOHN"
    assert (msg.pieces, msg.weight_kg) == (2, 31)


def test_expands_tag_count_into_consecutive_tags():
    assert parse_bsm(SAMPLE).tags == ["0081123456", "0081123457"]


def test_delete_message_sets_action():
    text = SAMPLE.replace("BSM\n", "BSM\nDEL\n", 1)
    assert parse_bsm(text).action == "DEL"


def test_pounds_are_converted_to_kilograms():
    msg = parse_bsm(SAMPLE.replace(".W/K/2/31", ".W/L/1/50"))
    assert msg.weight_kg == 23


def test_unknown_elements_become_warnings():
    msg = parse_bsm(SAMPLE.replace("ENDBSM", ".S/Y/12A\nENDBSM"))
    assert any(".S" in w for w in msg.warnings)


@pytest.mark.parametrize(
    "text, fragment",
    [
        ("HELLO\nENDBSM", "start with"),
        ("BSM\n.V/1LMEL\n.F/QF401/18OCT/SYD", "end with"),
        (SAMPLE.replace(".N/0081123456002\n", ""), ".N"),
        (SAMPLE.replace(".F/QF401/18OCT/SYD/Y", ".F/QF401"), "Invalid .F"),
        (SAMPLE.replace("0081123456002", "123"), "Invalid .N"),
    ],
)
def test_rejects_invalid_messages(text, fragment):
    with pytest.raises(BSMError, match=fragment.replace(".", r"\.")):
        parse_bsm(text)
