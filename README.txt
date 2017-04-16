Please, check http://eldhelmplatform.org for more details about this project.

Eldhelm platform is the application server running the entire back-end of the fantasy, card collecting game - Battlegrounds of Eldhelm (http://eldhelm.essenceworks.com)

Eldhelm platform features:

- Perl 5 implementation
- Works on both Linux and Windows
- Multithreaded architecture
- Reliable event driven, non-blocking IO 
- 2 way gracefull restart - worker threads restart or save and reload state from disk
- Abbility to handle multiple protocols on a single port
- A socket server - supports a custom built json protocol + authentication, latency detection, timeouts, guarantees message delivery in case of reconnects
- A http server - supports light http 1.0 + cookies, virtual hosting, url rewriting, https
- Supports SSL
- Extendable with other protocols
- MVC framework + advanced routing engine
- Publish-subscribe framework 
- Task scheduler
- Advanced MySQL Database abstraction layer framework
- A templating engine
- Bulk mailer
- A.I. framework
- Localization framework
- Testing framework