import Foundation

/// Stands in for the Places API. Swapping in Google Places means replacing this
/// type with a client that returns the same `City` / `Place` shapes.
enum SampleData {

    static let cities: [City] = [
        City(id: "lisbon", name: "Lisbon", country: "Portugal",
             tagline: "Tiled hills, custard tarts and the Atlantic light",
             coordinate: Coordinate(latitude: 38.7223, longitude: -9.1393)),
        City(id: "kyoto", name: "Kyoto", country: "Japan",
             tagline: "A thousand shrines and a river that runs through them",
             coordinate: Coordinate(latitude: 35.0116, longitude: 135.7681)),
        City(id: "mexico-city", name: "Mexico City", country: "Mexico",
             tagline: "Murals, mercados and the best breakfast on earth",
             coordinate: Coordinate(latitude: 19.4326, longitude: -99.1332))
    ]

    static func city(id: String) -> City {
        cities.first { $0.id == id } ?? cities[0]
    }

    static func place(id: String) -> Place? {
        places.first { $0.id == id }
    }

    static func places(in cityID: String) -> [Place] {
        places.filter { $0.cityID == cityID }
    }

    static let places: [Place] = lisbon + kyoto + mexicoCity

    // MARK: Lisbon

    private static let lisbon: [Place] = [
        Place(id: "lis-belem-tower", name: "Belém Tower", cityID: "lisbon", category: .attraction,
              neighborhood: "Belém", rating: 4.62, reviewCount: 18420, priceLevel: 2, typicalMinutes: 75,
              blurb: "16th-century river fort with terrace views",
              about: "A Manueline watchtower built to guard the mouth of the Tagus, now the postcard shot every visitor takes. Go early — the spiral stair up to the terrace is one-way and the queue builds fast after ten.",
              coordinate: Coordinate(latitude: 38.6916, longitude: -9.2160),
              tags: ["UNESCO", "River views", "Skip-the-line"]),

        Place(id: "lis-jeronimos", name: "Jerónimos Monastery", cityID: "lisbon", category: .museum,
              neighborhood: "Belém", rating: 4.78, reviewCount: 24110, priceLevel: 2, typicalMinutes: 105,
              blurb: "Vast cloisters carved like rope and coral",
              about: "The high point of Portuguese Manueline architecture. The church is free; the cloister is worth the ticket and the extra half hour. Vasco da Gama is buried just inside the west door.",
              coordinate: Coordinate(latitude: 38.6979, longitude: -9.2065),
              tags: ["UNESCO", "Architecture", "Quiet cloisters"]),

        Place(id: "lis-pasteis-belem", name: "Pastéis de Belém", cityID: "lisbon", category: .food,
              neighborhood: "Belém", rating: 4.51, reviewCount: 41230, priceLevel: 1, typicalMinutes: 40,
              blurb: "The original custard tart, since 1837",
              about: "Still baked to a recipe held by a handful of people. The takeaway line looks alarming but moves; the tiled back rooms almost always have a table if you walk past the counter.",
              coordinate: Coordinate(latitude: 38.6975, longitude: -9.2033),
              tags: ["Iconic", "Cash friendly", "Open early"]),

        Place(id: "lis-tram-28", name: "Tram 28", cityID: "lisbon", category: .activity,
              neighborhood: "Graça → Estrela", rating: 4.35, reviewCount: 9870, priceLevel: 1, typicalMinutes: 60,
              blurb: "Yellow tram through the oldest streets",
              about: "A working commuter line that happens to climb through Alfama, Graça and Estrela. Board at Martim Moniz for a seat, or ride it in reverse from Campo de Ourique to dodge the crowd.",
              coordinate: Coordinate(latitude: 38.7100, longitude: -9.1360),
              tags: ["Scenic", "Cheap", "Watch your bag"]),

        Place(id: "lis-castelo", name: "Castelo de São Jorge", cityID: "lisbon", category: .attraction,
              neighborhood: "Castelo", rating: 4.55, reviewCount: 31220, priceLevel: 2, typicalMinutes: 90,
              blurb: "Moorish walls above the whole city",
              about: "Ramparts you can walk end to end, peacocks in the gardens, and the widest view of the Baixa grid and the river. Sunset is spectacular and packed in equal measure.",
              coordinate: Coordinate(latitude: 38.7139, longitude: -9.1335),
              tags: ["Views", "Sunset", "Lots of steps"]),

        Place(id: "lis-alfama", name: "Alfama backstreets", cityID: "lisbon", category: .activity,
              neighborhood: "Alfama", rating: 4.71, reviewCount: 7640, priceLevel: 1, typicalMinutes: 120,
              blurb: "Get lost on purpose in the fado quarter",
              about: "The one district the 1755 earthquake spared. No route needed — walk downhill from the castle and let the laundry lines and tiled facades do the navigating.",
              coordinate: Coordinate(latitude: 38.7115, longitude: -9.1300),
              tags: ["Walkable", "Fado", "Free"]),

        Place(id: "lis-senhora-monte", name: "Miradouro da Senhora do Monte", cityID: "lisbon", category: .nature,
              neighborhood: "Graça", rating: 4.74, reviewCount: 12980, priceLevel: 1, typicalMinutes: 35,
              blurb: "The highest viewpoint in the city",
              about: "A pine-shaded terrace with the castle in the middle distance and the bridge beyond it. Bring something from the kiosk and stay for the light going down.",
              coordinate: Coordinate(latitude: 38.7186, longitude: -9.1315),
              tags: ["Sunset", "Free", "Shaded"]),

        Place(id: "lis-timeout", name: "Time Out Market", cityID: "lisbon", category: .food,
              neighborhood: "Cais do Sodré", rating: 4.42, reviewCount: 52310, priceLevel: 2, typicalMinutes: 75,
              blurb: "Thirty-odd kitchens under one iron roof",
              about: "A curated food hall in the old Mercado da Ribeira. Good for a group that can't agree: everything from Michelin-chef counters to a proper bifana in the same room.",
              coordinate: Coordinate(latitude: 38.7067, longitude: -9.1459),
              tags: ["Groups", "Late", "Busy at 8pm"]),

        Place(id: "lis-azulejo", name: "National Tile Museum", cityID: "lisbon", category: .museum,
              neighborhood: "Beato", rating: 4.66, reviewCount: 8110, priceLevel: 2, typicalMinutes: 80,
              blurb: "Five centuries of azulejo in a convent",
              about: "Slightly out of the way, which is why it stays calm. The 23-metre panorama of pre-earthquake Lisbon on the top floor is the reason to make the trip.",
              coordinate: Coordinate(latitude: 38.7250, longitude: -9.1136),
              tags: ["Rainy day", "Uncrowded", "Café inside"]),

        Place(id: "lis-lx-factory", name: "LX Factory", cityID: "lisbon", category: .activity,
              neighborhood: "Alcântara", rating: 4.44, reviewCount: 19870, priceLevel: 2, typicalMinutes: 100,
              blurb: "Print works turned studios and rooftops",
              about: "A 19th-century industrial block under the bridge, now bookshops, design studios and a lot of good coffee. Sunday brings a flea market to the main lane.",
              coordinate: Coordinate(latitude: 38.7030, longitude: -9.1786),
              tags: ["Shopping", "Coffee", "Sunday market"]),

        Place(id: "lis-comercio", name: "Praça do Comércio", cityID: "lisbon", category: .attraction,
              neighborhood: "Baixa", rating: 4.68, reviewCount: 44190, priceLevel: 1, typicalMinutes: 45,
              blurb: "The city's front door onto the river",
              about: "Rebuilt after the earthquake as a statement of confidence: arcades on three sides, the Tagus on the fourth. Climb the Rua Augusta arch for the view back up the grid.",
              coordinate: Coordinate(latitude: 38.7075, longitude: -9.1364),
              tags: ["Central", "Free", "River"]),

        Place(id: "lis-pensao-amor", name: "Pensão Amor", cityID: "lisbon", category: .nightlife,
              neighborhood: "Cais do Sodré", rating: 4.38, reviewCount: 6420, priceLevel: 2, typicalMinutes: 90,
              blurb: "A former brothel, now a very good bar",
              about: "Painted ceilings, a burlesque stage and a bookshop off the landing. Pink Street is right outside if the night keeps going.",
              coordinate: Coordinate(latitude: 38.7078, longitude: -9.1440),
              tags: ["Late night", "Cocktails", "Live music"])
    ]

    // MARK: Kyoto

    private static let kyoto: [Place] = [
        Place(id: "kyo-fushimi", name: "Fushimi Inari Taisha", cityID: "kyoto", category: .attraction,
              neighborhood: "Fushimi", rating: 4.81, reviewCount: 61240, priceLevel: 1, typicalMinutes: 150,
              blurb: "Ten thousand vermilion gates up a mountain",
              about: "The full loop to the summit takes about two hours and thins out dramatically past the Yotsutsuji junction. Open around the clock — before seven you may have the lower gates to yourself.",
              coordinate: Coordinate(latitude: 34.9671, longitude: 135.7727),
              tags: ["Open 24h", "Hiking", "Go early"]),

        Place(id: "kyo-kinkakuji", name: "Kinkaku-ji", cityID: "kyoto", category: .attraction,
              neighborhood: "Kita", rating: 4.72, reviewCount: 48310, priceLevel: 2, typicalMinutes: 60,
              blurb: "The Golden Pavilion over a still pond",
              about: "A single fixed route around the pond, so it's quick. The reflection is best on a windless morning; the tea garden at the exit is a decent excuse to slow down.",
              coordinate: Coordinate(latitude: 35.0394, longitude: 135.7292),
              tags: ["UNESCO", "Short visit", "Photogenic"]),

        Place(id: "kyo-arashiyama", name: "Arashiyama Bamboo Grove", cityID: "kyoto", category: .nature,
              neighborhood: "Arashiyama", rating: 4.58, reviewCount: 39870, priceLevel: 1, typicalMinutes: 70,
              blurb: "A green corridor that hums in the wind",
              about: "The grove itself is a ten-minute walk; pair it with Tenryū-ji's garden next door and the riverbank at Togetsukyō to make an afternoon of it.",
              coordinate: Coordinate(latitude: 35.0170, longitude: 135.6717),
              tags: ["Free", "Go at dawn", "River nearby"]),

        Place(id: "kyo-nishiki", name: "Nishiki Market", cityID: "kyoto", category: .food,
              neighborhood: "Nakagyō", rating: 4.40, reviewCount: 33120, priceLevel: 2, typicalMinutes: 80,
              blurb: "Five covered blocks of Kyoto's kitchen",
              about: "Pickles, tamagoyaki, sesame tofu, knives. Eating while walking is frowned on — most stalls have a spot to stand and finish what you bought.",
              coordinate: Coordinate(latitude: 35.0050, longitude: 135.7649),
              tags: ["Street food", "Covered", "Closes ~6pm"]),

        Place(id: "kyo-kiyomizu", name: "Kiyomizu-dera", cityID: "kyoto", category: .attraction,
              neighborhood: "Higashiyama", rating: 4.75, reviewCount: 52990, priceLevel: 2, typicalMinutes: 95,
              blurb: "A wooden stage above the maple valley",
              about: "Built without a single nail. Walk up through Sannenzaka's preserved lanes rather than taking a cab to the gate — the approach is half the point.",
              coordinate: Coordinate(latitude: 34.9948, longitude: 135.7850),
              tags: ["UNESCO", "Autumn colour", "Uphill walk"]),

        Place(id: "kyo-gion", name: "Gion at dusk", cityID: "kyoto", category: .activity,
              neighborhood: "Gion", rating: 4.49, reviewCount: 21430, priceLevel: 1, typicalMinutes: 75,
              blurb: "Lantern-lit teahouse lanes",
              about: "Hanamikoji and the Shirakawa canal are the two streets worth your time. Photography is restricted on the private lanes and the signs mean it.",
              coordinate: Coordinate(latitude: 35.0037, longitude: 135.7752),
              tags: ["Evening", "Free", "Respect signs"]),

        Place(id: "kyo-philosopher", name: "Philosopher's Path", cityID: "kyoto", category: .nature,
              neighborhood: "Sakyō", rating: 4.53, reviewCount: 14760, priceLevel: 1, typicalMinutes: 65,
              blurb: "Two canal-side kilometres of cherry trees",
              about: "Named for a professor who walked it daily. Runs between Ginkaku-ji and Nanzen-ji, so it works as the connective tissue of an eastern-hills day.",
              coordinate: Coordinate(latitude: 35.0270, longitude: 135.7947),
              tags: ["Walkable", "Cherry blossom", "Cafés"]),

        Place(id: "kyo-pontocho", name: "Pontochō Alley", cityID: "kyoto", category: .nightlife,
              neighborhood: "Nakagyō", rating: 4.46, reviewCount: 17820, priceLevel: 3, typicalMinutes: 110,
              blurb: "One narrow lane, a hundred kitchens",
              about: "Barely wide enough for two people, running along the Kamo river. In summer the restaurants build yuka decks out over the water — book if you want one.",
              coordinate: Coordinate(latitude: 35.0060, longitude: 135.7710),
              tags: ["Dinner", "Book ahead", "Riverside"])
    ]

    // MARK: Mexico City

    private static let mexicoCity: [Place] = [
        Place(id: "mex-frida", name: "Museo Frida Kahlo", cityID: "mexico-city", category: .museum,
              neighborhood: "Coyoacán", rating: 4.69, reviewCount: 38210, priceLevel: 2, typicalMinutes: 90,
              blurb: "La Casa Azul, kept as she left it",
              about: "Her studio, her wheelchair at the easel, her garden. Tickets are timed and sell out days ahead — book before you fly, not the morning of.",
              coordinate: Coordinate(latitude: 19.3550, longitude: -99.1626),
              tags: ["Book ahead", "Timed entry", "Small rooms"]),

        Place(id: "mex-antropologia", name: "Museo Nacional de Antropología", cityID: "mexico-city", category: .museum,
              neighborhood: "Chapultepec", rating: 4.85, reviewCount: 57640, priceLevel: 2, typicalMinutes: 180,
              blurb: "The finest pre-Hispanic collection anywhere",
              about: "Twenty-three halls around a courtyard with a vast concrete umbrella. Nobody finishes it — pick Teotihuacán, Mexica and Maya and let the rest go.",
              coordinate: Coordinate(latitude: 19.4260, longitude: -99.1863),
              tags: ["Half day", "Air conditioned", "Closed Mondays"]),

        Place(id: "mex-zocalo", name: "Zócalo", cityID: "mexico-city", category: .attraction,
              neighborhood: "Centro Histórico", rating: 4.60, reviewCount: 45120, priceLevel: 1, typicalMinutes: 60,
              blurb: "Aztec ruins, cathedral and a flag the size of a house",
              about: "One of the largest squares in the world, built on the ruins of Tenochtitlán. Templo Mayor is on the corner and the cathedral is visibly sinking into the lakebed.",
              coordinate: Coordinate(latitude: 19.4326, longitude: -99.1332),
              tags: ["Central", "Free", "Templo Mayor"]),

        Place(id: "mex-bellas-artes", name: "Palacio de Bellas Artes", cityID: "mexico-city", category: .attraction,
              neighborhood: "Centro Histórico", rating: 4.79, reviewCount: 29840, priceLevel: 2, typicalMinutes: 75,
              blurb: "Art nouveau outside, art deco in",
              about: "Rivera's remade *Man at the Crossroads* is upstairs. For the classic photo of the dome, take the lift to the Sears café terrace across the street.",
              coordinate: Coordinate(latitude: 19.4352, longitude: -99.1412),
              tags: ["Murals", "Ballet Folklórico", "Café view"]),

        Place(id: "mex-contramar", name: "Contramar", cityID: "mexico-city", category: .food,
              neighborhood: "Roma Norte", rating: 4.72, reviewCount: 12340, priceLevel: 3, typicalMinutes: 120,
              blurb: "The long lunch this city is famous for",
              about: "Tuna tostadas and the red-and-green pescado a la talla. It is a lunch place — book two weeks out, arrive at three, leave when it gets dark.",
              coordinate: Coordinate(latitude: 19.4160, longitude: -99.1690),
              tags: ["Book ahead", "Lunch only", "Seafood"]),

        Place(id: "mex-coyoacan-market", name: "Mercado de Coyoacán", cityID: "mexico-city", category: .food,
              neighborhood: "Coyoacán", rating: 4.51, reviewCount: 18990, priceLevel: 1, typicalMinutes: 60,
              blurb: "Tostadas, flowers and a lot of noise",
              about: "The tostada counters in the middle are the draw. Ten minutes from the Kahlo house, which makes it the obvious pairing.",
              coordinate: Coordinate(latitude: 19.3506, longitude: -99.1620),
              tags: ["Cheap eats", "Cash", "Near Frida"]),

        Place(id: "mex-xochimilco", name: "Xochimilco canals", cityID: "mexico-city", category: .nature,
              neighborhood: "Xochimilco", rating: 4.44, reviewCount: 26310, priceLevel: 2, typicalMinutes: 210,
              blurb: "Painted boats on the last Aztec waterways",
              about: "Hire a trajinera by the hour — the price is per boat, not per person, so it rewards a group. Saturdays are a floating party; weekdays are birds and chinampas.",
              coordinate: Coordinate(latitude: 19.2600, longitude: -99.1030),
              tags: ["Half day", "Groups", "Bring cash"]),

        Place(id: "mex-teotihuacan", name: "Teotihuacán", cityID: "mexico-city", category: .attraction,
              neighborhood: "50 km northeast", rating: 4.86, reviewCount: 41870, priceLevel: 2, typicalMinutes: 300,
              blurb: "The Avenue of the Dead at sunrise",
              about: "A full day out. Buses run from Terminal Norte in about an hour; go on the first one, do the Sun and Moon pyramids before the heat, and be back for a late lunch.",
              coordinate: Coordinate(latitude: 19.6925, longitude: -98.8438),
              tags: ["Day trip", "Start early", "Sun protection"])
    ]
}
