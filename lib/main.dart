import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() => runApp(ChangeNotifierProvider(create: (_) => Cart(), child: const SareeApp()));

class CartItem {
  CartItem({required this.name, required this.price, this.quantity = 1});
  final String name; final int price; int quantity;
  int get subtotal => price * quantity;
}
class Cart extends ChangeNotifier {
  final List<CartItem> items = [];
  void add(String name, int price) { final i=items.indexWhere((x)=>x.name==name); if(i>=0){items[i].quantity++;}else{items.add(CartItem(name:name,price:price));} notifyListeners(); }
  void change(CartItem item,int delta){item.quantity+=delta;if(item.quantity<=0)items.remove(item);notifyListeners();}
  int get count => items.fold(0,(s,x)=>s+x.quantity);
  int get subtotal => items.fold(0,(s,x)=>s+x.subtotal);
  int get delivery => items.isEmpty ? 0 : 1000;
  int get total => subtotal+delivery;
  void clear(){items.clear();notifyListeners();}
}
class SareeApp extends StatelessWidget { const SareeApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,title:'سريع',theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFFFF6B35))),home:const Directionality(textDirection:TextDirection.rtl,child:Home()));
}
class Home extends StatelessWidget { const Home({super.key});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('سريع - توصيل الطعام في رداع'),actions:[Consumer<Cart>(builder:(_,c,__)=>Badge(label:Text(c.count.toString()),isLabelVisible:c.count>0,child:IconButton(icon:const Icon(Icons.shopping_cart),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CartPage())))))]),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Card(child:ListTile(leading:Icon(Icons.location_on),title:Text('عنوان التوصيل'),subtitle:Text('رداع، اليمن - اختر الموقع عند تأكيد الطلب'))),
      const Text('المطاعم المتاحة',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      ...['مطعم الذوق','مطعم رداع الشعبي'].map((n)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.restaurant)),title:Text(n),subtitle:const Text('⭐ 4.7 • حوالي 30 دقيقة'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Restaurant(name:n))))))
    ]));
}
class Restaurant extends StatelessWidget { final String name; const Restaurant({super.key,required this.name});
  @override Widget build(BuildContext context){final foods=[['وجبة دجاج',3500],['برجر لحم',3000],['وجبة مشويات',5000]];return Scaffold(appBar:AppBar(title:Text(name)),body:ListView(padding:const EdgeInsets.all(16),children:foods.map((f)=>Card(child:ListTile(title:Text(f[0] as String),subtitle:Text('${f[1]} ريال يمني'),trailing:IconButton(icon:const Icon(Icons.add_circle),onPressed:()=>context.read<Cart>().add(f[0] as String,f[1] as int)))).toList()));}
}
class CartPage extends StatelessWidget { const CartPage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('سلة الطلب')),body:Consumer<Cart>(builder:(_,c,__){if(c.items.isEmpty)return const Center(child:Text('السلة فارغة'));return Padding(padding:const EdgeInsets.all(16),child:Column(children:[Expanded(child:ListView(children:c.items.map((x)=>ListTile(title:Text(x.name),subtitle:Text('${x.subtotal} ريال'),leading:IconButton(icon:const Icon(Icons.remove_circle_outline),onPressed:()=>c.change(x,-1)),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('${x.quantity}'),IconButton(icon:const Icon(Icons.add_circle_outline),onPressed:()=>c.change(x,1))]))).toList())),Align(alignment:Alignment.centerRight,child:Text('التوصيل: ${c.delivery} ريال\nالإجمالي: ${c.total} ريال',style:const TextStyle(fontWeight:FontWeight.bold))),const SizedBox(height:12),ElevatedButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CheckoutPage())),child:const Text('متابعة الطلب'))]));}));
}
class CheckoutPage extends StatefulWidget { const CheckoutPage({super.key}); @override State<CheckoutPage> createState()=>_CheckoutPageState(); }
class _CheckoutPageState extends State<CheckoutPage>{final address=TextEditingController(text:'رداع - حدد عنوانك بالتفصيل');@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تأكيد الطلب')),body:Padding(padding:const EdgeInsets.all(16),child:Column(children:[TextField(controller:address,decoration:const InputDecoration(labelText:'عنوان التوصيل',border:OutlineInputBorder())),const SizedBox(height:12),const ListTile(leading:Icon(Icons.payments),title:Text('الدفع عند الاستلام')),ElevatedButton(onPressed:(){context.read<Cart>().clear();Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const Tracking()),(_)=>false);},child:const Text('تأكيد الطلب'))])));}
class Tracking extends StatefulWidget { const Tracking({super.key}); @override State<Tracking> createState()=>_TrackingState(); }
class _TrackingState extends State<Tracking>{int step=0;bool cancelled=false;final states=['تم إرسال الطلب','قبل المطعم الطلب','جاري تحضير الطلب','المندوب في الطريق','تم التوصيل'];@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تتبع الطلب')),body:Padding(padding:const EdgeInsets.all(20),child:Column(children:[const Icon(Icons.delivery_dining,size:80),const SizedBox(height:10),if(cancelled)const Text('تم إلغاء الطلب')else Expanded(child:ListView(children:List.generate(states.length,(i)=>ListTile(leading:Icon(i<=step?Icons.check_circle:Icons.radio_button_unchecked),title:Text(states[i]))))),if(!cancelled&&step<states.length-1)ElevatedButton(onPressed:()=>setState(()=>step++),child:const Text('تحديث حالة الطلب')),if(!cancelled&&step<2)OutlinedButton(onPressed:()=>setState(()=>cancelled=true),child:const Text('إلغاء الطلب'))])));}
