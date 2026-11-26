-- Indsæt denne blok i ox_inventory/data/items.lua (inden den sidste "}").
-- Kopiér billederne i images/ til ox_inventory/web/images/.

	-- mach1ne_counterfeit
	['cf_paper'] = {
		label = 'Bomuldspapir', weight = 100, stack = true,
		description = 'Blankt papir med bomuldsfibre - kommes i trykpressen',
		client = { image = 'm1f_cf_paper.png' },
	},
	['cf_ink'] = {
		label = 'Sikkerhedsblæk', weight = 300, stack = true,
		description = 'Grønt blæk til trykpressen',
		client = { image = 'm1f_cf_ink.png' },
	},
	['cf_sheet_wet'] = {
		label = 'Våde trykark', weight = 60, stack = true,
		description = 'Nytrykte ark - skal hænge til tørre',
		client = { image = 'm1f_cf_sheet_wet.png' },
	},
	['cf_sheet'] = {
		label = 'Trykark', weight = 50, stack = true,
		description = '8 sedler pr. ark - skæres i skæremaskinen',
		client = { image = 'm1f_cf_sheet.png' },
	},
	['cf_bills'] = {
		label = 'Løse sedler', weight = 2, stack = true,
		description = 'Falske 1000-sedler - tælles og bundtes i sedeltælleren',
		client = { image = 'm1f_cf_bills.png' },
	},
	['cf_band'] = {
		label = 'Banderole', weight = 5, stack = true,
		description = 'Papirbånd til et bundt sedler',
		client = { image = 'm1f_cf_band.png' },
	},
	['cf_bundle'] = {
		label = 'Bundt sedler', weight = 60, stack = true,
		description = 'Et bundt 1000-sedler',
		client = { image = 'm1f_cf_bundle.png' },
	},
	['cf_scanner'] = {
		label = 'UV-seddelscanner', weight = 400, stack = true, close = true, consume = 0,
		description = 'Afslører falske sedler. Brug den med bundter på dig',
		client = { image = 'm1f_cf_scanner.png', export = 'mach1ne_counterfeit.useScanner' },
	},
	['cf_press'] = {
		label = 'Trykpresse', weight = 60000, stack = true, close = true, consume = 0,
		description = 'Stil den op hvor du vil - den larmer',
		client = { image = 'm1f_cf_press.png', export = 'mach1ne_counterfeit.useStation' },
	},
	['cf_dryline'] = {
		label = 'Tørresnor', weight = 5000, stack = true, close = true, consume = 0,
		description = 'Stil den op hvor du vil',
		client = { image = 'm1f_cf_dryline.png', export = 'mach1ne_counterfeit.useStation' },
	},
	['cf_cutter'] = {
		label = 'Skæremaskine', weight = 25000, stack = true, close = true, consume = 0,
		description = 'Stil den op hvor du vil',
		client = { image = 'm1f_cf_cutter.png', export = 'mach1ne_counterfeit.useStation' },
	},
	['cf_counter'] = {
		label = 'Sedeltæller', weight = 3500, stack = true, close = true, consume = 0,
		description = 'Stil den op hvor du vil - fx på et arbejdsbord',
		client = { image = 'm1f_cf_counter.png', export = 'mach1ne_counterfeit.useStation' },
	},
	['cf_table'] = {
		label = 'Arbejdsbord', weight = 15000, stack = true, close = true, consume = 0,
		description = 'Stil det op hvor du vil',
		client = { image = 'm1f_cf_table.png', export = 'mach1ne_counterfeit.useProp' },
	},
