use demo

db.ship.insertOne( { name: 'Titanic', line: 'White Star', num_funnels: 4 } );
db.ship.insertOne( { name: 'Olympic', line: 'White Star', num_funnels: 4 } );
db.ship.insertOne( { name: 'Queen Mary', line: 'Cunard', num_funnels: 3 } );

db.ship.find ()
