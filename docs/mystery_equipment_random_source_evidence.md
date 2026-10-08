# Mystery equipment random instance source evidence

This is a source record for the registered project mapping used by the mystery instance rule. It does not adopt the original curse, equip-lock, or remove-curse behavior.

## Primary formula source

* `dev_art_sources/reference/original_gameofmir/M2Server/ItmUnit.pas`
* SHA256: `CE0F5233E5F1E1D995BC0CA64764BF86017B4CF881A4DD8EA1821C2EBBAE6B6C`
* `GetRandomRange`: lines 88-95. It performs `nCount` Bernoulli trials with success probability `1/nRate`.
* Helmet family (`StdMode=15`): lines 389-444.
* Ring family (`StdMode=22,23`): lines 445-495.
* Project-registered bracelet family (`StdMode=24,26`): lines 496-550.
* Accessory stat and Need application (`btValue[0..6]`): lines 142-157.

## Primary parameter source

* `dev_art_sources/reference/original_gameofmir/M2Server/M2Share.pas`
* SHA256: `9E1505BE616D55A362151150BA92712B9C8439F0A32E35B13C666AE07A33C085`
* Defaults: lines 1929-1958.
* Helmet: AC/MAC 4 trials at rate 20; DC/MC/SC 3 trials at rate 30.
* Ring: AC/MAC 4 trials at rate 20; DC/MC/SC 6 trials at rate 20.
* Bracelet mapping: AC/MAC 5 trials at rate 20; DC/MC/SC 5 trials at rate 30.

## Project mapping

* Item 218 (`equipment_attribute_master.json` row 74, category `头盔`) uses helmet family.
* Item 219 (row 75, category `手镯`) uses the registered bracelet family.
* Item 220 (row 76, category `戒指`) uses ring family.

The item-to-family binding is the project's registered canonical-category mapping. It is not a claim that the old server source contains these project item IDs.

The HardCore rule rolls only the five instance stats and their corresponding requirement. Base durability remains the equipment master value. New rolls are bound to the existing drop digest and are not rerolled on equip. Legacy instances without a roll remain valid.
