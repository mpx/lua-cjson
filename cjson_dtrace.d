provider cjson {
	probe new__entry();
	probe encode__start();
	probe encode__done(int len, char *);
};
