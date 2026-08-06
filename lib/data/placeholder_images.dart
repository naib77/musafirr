/// Placeholder images from Unsplash for listings
class PlaceholderImages {
  PlaceholderImages._();

  // Property images - Living rooms and interiors
  static const List<String> livingRooms = [
    'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=800',
    'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=800',
    'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=800',
    'https://images.unsplash.com/photo-1493809842364-78817add7ffb?w=800',
    'https://images.unsplash.com/photo-1556020685-ae41abfc9365?w=800',
  ];

  // Bedrooms
  static const List<String> bedrooms = [
    'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?w=800',
    'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=800',
    'https://images.unsplash.com/photo-1540518614846-7eded433c457?w=800',
    'https://images.unsplash.com/photo-1560185893-a55cbc8c57e8?w=800',
    'https://images.unsplash.com/photo-1558442074-3c19857bc1dc?w=800',
  ];

  // Kitchens
  static const List<String> kitchens = [
    'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800',
    'https://images.unsplash.com/photo-1556909172-54557c7e4fb7?w=800',
    'https://images.unsplash.com/photo-1484154218962-a197022b25ba?w=800',
  ];

  // Bathrooms
  static const List<String> bathrooms = [
    'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?w=800',
    'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?w=800',
  ];

  // Exteriors and views
  static const List<String> exteriors = [
    'https://images.unsplash.com/photo-1564013799919-ab600027ffc6?w=800',
    'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800',
    'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=800',
    'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800',
    'https://images.unsplash.com/photo-1605276374104-dee2a0ed3cd6?w=800',
  ];

  // Apartments
  static const List<String> apartments = [
    'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=800',
    'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=800',
    'https://images.unsplash.com/photo-1536376072261-38c75010e6c9?w=800',
    'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?w=800',
  ];

  // Villas and luxury
  static const List<String> villas = [
    'https://images.unsplash.com/photo-1613490493576-7fde63acd811?w=800',
    'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=800',
    'https://images.unsplash.com/photo-1600566753190-17f0baa2a6c3?w=800',
    'https://images.unsplash.com/photo-1600047509807-ba8f99d2cdde?w=800',
  ];

  // Single rooms
  static const List<String> rooms = [
    'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=800',
    'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?w=800',
    'https://images.unsplash.com/photo-1540518614846-7eded433c457?w=800',
  ];

  // Avatar placeholders - using ui-avatars.com which is CORS-friendly
  static const List<String> _avatarNames = [
    'Ahmed',
    'Fatima',
    'Karim',
    'Nadia',
    'Omar',
    'Sara',
    'Yusuf',
    'Aisha',
    'Hassan',
    'Layla',
    'Ibrahim',
    'Maryam',
    'Ali',
    'Zainab',
    'Tariq',
  ];

  static String avatar(int index) {
    final name = _avatarNames[index % _avatarNames.length];
    final colors = ['0B7285', '1098AD', '0CA678', '37B24D', '7048E8'];
    final bg = colors[index % colors.length];
    return 'https://ui-avatars.com/api/?name=$name&background=$bg&color=fff&size=150';
  }

  // Get a set of images for a listing based on index
  static List<String> forListing(int index) {
    final sets = [
      [livingRooms[0], bedrooms[0], kitchens[0], bathrooms[0], exteriors[0]],
      [apartments[0], bedrooms[1], livingRooms[1], kitchens[1], bathrooms[1]],
      [villas[0], livingRooms[2], bedrooms[2], exteriors[1], kitchens[2]],
      [exteriors[2], apartments[1], bedrooms[3], livingRooms[3], bathrooms[0]],
      [villas[1], bedrooms[4], livingRooms[4], exteriors[3], kitchens[0]],
      [apartments[2], rooms[0], kitchens[1], bathrooms[1], exteriors[4]],
      [villas[2], livingRooms[0], bedrooms[0], exteriors[0], kitchens[2]],
      [exteriors[1], apartments[3], bedrooms[1], livingRooms[1], bathrooms[0]],
      [villas[3], rooms[1], livingRooms[2], kitchens[0], exteriors[2]],
      [apartments[0], bedrooms[2], rooms[2], bathrooms[1], exteriors[3]],
      [livingRooms[3], villas[0], bedrooms[3], kitchens[1], exteriors[4]],
      [rooms[0], apartments[1], livingRooms[4], bathrooms[0], exteriors[0]],
      [villas[1], bedrooms[4], apartments[2], kitchens[2], exteriors[1]],
      [exteriors[2], livingRooms[0], rooms[1], bathrooms[1], villas[2]],
      [apartments[3], bedrooms[0], villas[3], kitchens[0], exteriors[3]],
    ];
    return sets[index % sets.length];
  }
}
