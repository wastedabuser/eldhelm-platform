{
	server => {
		name   => "eldhelm",
		host   => "127.0.0.1",
		port   => 80,
		logger => {
			logs => {
				access  => ["stdout"],
				general => ["stdout"],
				debug   => ["stdout"],
				error   => ["stderr"],
			},
		},
		acceptProtocols => ["Http"],
		http            => { directoryIndex => "controller:quickStart:index" },
	},
}
