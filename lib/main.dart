import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/data/journal_store.dart';
import 'src/data/attachment_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  Future<JournalStore> openStorage() async {
    await AttachmentStorage.open();
    return JournalStore.open();
  }

  late Future<JournalStore> store = openStorage();
  @override
  Widget build(BuildContext context) => FutureBuilder<JournalStore>(
    future: store,
    builder: (context, snapshot) {
      if (snapshot.hasData) return JournalApp(store: snapshot.data!);
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Your journal could not be opened.'),
                      const Text('Check device storage and try again.'),
                      TextButton(
                        onPressed: () => setState(() {
                          store = openStorage();
                        }),
                        child: const Text('Try again'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}
