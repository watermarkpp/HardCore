#include "crowd_geometry_kernel.h"
#include "core/math/geometry_2d.h"
#include <cmath>
#include <cstring>
#include <limits>
#include <type_traits>
#if defined(__FAST_MATH__) || defined(_M_FP_FAST)
#error Crowd geometry requires the pinned precise Godot arithmetic flags.
#endif

namespace hardcore::simulation::crowd {
static_assert(sizeof(real_t)==4, "Crowd parity is pinned to single precision Godot Vector2.");
namespace {
constexpr uint32_t INPUT_MAGIC=0x48434331, OUTPUT_MAGIC=0x48434332;
template<typename T> void write(std::vector<uint8_t>&b,const T &v) {
    static_assert(std::is_trivially_copyable_v<T>); size_t n=b.size();b.resize(n+sizeof(T));std::memcpy(b.data()+n,&v,sizeof(T));
}
struct Reader {
    const std::vector<uint8_t>&b;size_t at=0;
    template<typename T> bool read(T &v) {if(at>b.size()||b.size()-at<sizeof(T))return false;std::memcpy(&v,b.data()+at,sizeof(T));at+=sizeof(T);return true;}
};
bool finite(Vector2 v){return std::isfinite(v.x)&&std::isfinite(v.y);}
double source_max(double a,double b){return a>b?a:b;}
double source_min(double a,double b){return a<b?a:b;}
void write_vector(std::vector<uint8_t>&b,Vector2 v){write(b,v.x);write(b,v.y);}
bool read_vector(Reader&r,Vector2&v){return r.read(v.x)&&r.read(v.y);}
bool valid(const Query&q){return static_cast<uint8_t>(q.kind)<=2&&finite(q.a)&&finite(q.b)&&std::isfinite(q.own_radius)&&std::isfinite(q.own_margin)&&std::isfinite(q.epsilon)&&q.epsilon>0.0&&(q.kind!=Kind::CONTACT||q.b.length_squared()>0.0f);}
bool valid(const Peer&p){return p.runtime_id>0&&p.runtime_id<=INT64_MAX&&p.life>0&&p.pose_revision>0&&p.radius_revision>0&&p.map>=0&&finite(p.center)&&std::isfinite(p.radius)&&std::isfinite(p.margin);}
}

bool core_crossed(Vector2 a,Vector2 b,Vector2 c,double ra,double rb,double eps) {
    // scripts/monster_ai_package/policy.gd:core_crossed, identical branch order.
    const double r=source_max(0.0,ra+rb);
    const double before=a.distance_squared_to(c);
    if(before<r*r) return (b-a).dot(a-c)<-eps || b.distance_squared_to(c)<before-eps;
    const Vector2 q=Geometry2D::get_closest_point_to_segment(c,a,b);
    return q.distance_squared_to(c)<r*r-eps;
}
double free_ray_extent(Vector2 origin,Vector2 direction,Vector2 center,double radius,double extent,double eps) {
    // enemy_owner_crowd_position.gd:_free_ray_extent. No normalization/approx.
    const Vector2 offset=origin-center;
    const double toward=offset.dot(direction);
    const double clearance=static_cast<double>(offset.length_squared())-radius*radius;
    if(clearance<=0.0)return toward<0.0?0.0:extent;
    if(toward>=0.0)return extent;
    const double square=direction.length_squared();
    const double discriminant=toward*toward-square*clearance;
    if(discriminant<0.0)return extent;
    const double entry=(-toward-std::sqrt(discriminant))/square;
    return source_min(extent,source_max(0.0,entry-eps/std::sqrt(square)));
}
Row evaluate(const Query&q,const Peer&p) {
    Row r;
    if(q.kind==Kind::MOTION){
        const Vector2 low(source_min(q.a.x,q.b.x),source_min(q.a.y,q.b.y));
        const Vector2 high(source_max(q.a.x,q.b.x),source_max(q.a.y,q.b.y));
        const double radius=source_max(0.0,q.own_radius+p.radius)+q.epsilon;
        r.envelope=!(p.center.x<static_cast<double>(low.x)-radius||p.center.x>static_cast<double>(high.x)+radius||p.center.y<static_cast<double>(low.y)-radius||p.center.y>static_cast<double>(high.y)+radius);
        // Pure preparation may compute a core for an ineligible peer. S still
        // observes this value only after the original live eligibility calls.
        r.crossed=core_crossed(q.a,q.b,p.center,q.own_radius,p.radius,q.epsilon);
    }else if(q.kind==Kind::DESTINATION){
        const double radius=source_max(0.0,q.own_radius+p.radius);
        // Preserve the source's negative >= branch, including unordered values.
        r.crossed=!(q.b.distance_squared_to(p.center)>=radius*radius-q.epsilon);
        r.envelope=r.crossed;
    }else{
        const double radius=q.own_radius+p.radius+q.own_margin+p.margin;
        // GDScript center.x-origin.x is scalar double, unlike Vector2 subtraction.
        r.envelope=source_max(std::abs(static_cast<double>(p.center.x)-q.a.x),std::abs(static_cast<double>(p.center.y)-q.a.y))<=1.0+radius;
        r.limit=free_ray_extent(q.a,q.b,p.center,radius,1.0,q.epsilon);
    }
    return r;
}
bool same_query(const Query&a,const Query&b){return a.kind==b.kind&&a.a==b.a&&a.b==b.b&&a.own_radius==b.own_radius&&a.own_margin==b.own_margin&&a.epsilon==b.epsilon;}
bool same_peer(const Peer&a,const Peer&b){return a.runtime_id==b.runtime_id&&a.life==b.life&&a.pose_revision==b.pose_revision&&a.radius_revision==b.radius_revision&&a.map==b.map&&a.center==b.center&&a.radius==b.radius&&a.margin==b.margin;}
std::shared_ptr<const FrozenInput> freeze_input(const Input&in,uint64_t version){
    if(!valid(in.query)||in.peers.size()>UINT32_MAX)return nullptr;
    auto frozen=std::make_shared<FrozenInput>();frozen->input_version=version;auto &b=frozen->bytes;
    write(b,INPUT_MAGIC);write(b,static_cast<uint8_t>(in.query.kind));write_vector(b,in.query.a);write_vector(b,in.query.b);write(b,in.query.own_radius);write(b,in.query.own_margin);write(b,in.query.epsilon);write(b,static_cast<uint32_t>(in.peers.size()));
    for(const Peer&p:in.peers){if(!valid(p))return nullptr;write(b,p.runtime_id);write(b,p.life);write(b,p.pose_revision);write(b,p.radius_revision);write(b,p.map);write_vector(b,p.center);write(b,p.radius);write(b,p.margin);}
    return frozen;
}
bool thaw_input(const FrozenInput&f,Input&out){
    Reader r{f.bytes};uint32_t magic=0,count=0;uint8_t kind=0;
    if(!r.read(magic)||magic!=INPUT_MAGIC||!r.read(kind)||kind>2||!read_vector(r,out.query.a)||!read_vector(r,out.query.b)||!r.read(out.query.own_radius)||!r.read(out.query.own_margin)||!r.read(out.query.epsilon)||!r.read(count))return false;
    out.query.kind=static_cast<Kind>(kind);if(!valid(out.query))return false;
    constexpr size_t PEER_BYTES=5*sizeof(uint64_t)+2*sizeof(real_t)+2*sizeof(double);
    if(count>(f.bytes.size()-r.at)/PEER_BYTES)return false;
    out.peers.resize(count);
    for(Peer&p:out.peers)if(!r.read(p.runtime_id)||!r.read(p.life)||!r.read(p.pose_revision)||!r.read(p.radius_revision)||!r.read(p.map)||!read_vector(r,p.center)||!r.read(p.radius)||!r.read(p.margin)||!valid(p))return false;
    return r.at==f.bytes.size();
}
bool decode_output(const std::vector<uint8_t>&b,Output&out){
    Reader r{b};uint32_t magic=0,count=0;if(!r.read(magic)||magic!=OUTPUT_MAGIC||!r.read(count)||count>(b.size()-r.at)/(2+sizeof(double)))return false;
    out.rows.resize(count);for(Row&row:out.rows){uint8_t envelope=0,crossed=0;if(!r.read(envelope)||!r.read(crossed)||envelope>1||crossed>1||!r.read(row.limit)||!std::isfinite(row.limit))return false;row.envelope=envelope;row.crossed=crossed;}
    return r.at==b.size();
}
void batch_kernel(const FrozenInput&f,std::vector<uint8_t>&b,void*){
    Input input;b.clear();if(!thaw_input(f,input))return;
    write(b,OUTPUT_MAGIC);write(b,static_cast<uint32_t>(input.peers.size()));
    for(const Peer&p:input.peers){const Row row=evaluate(input.query,p);write(b,static_cast<uint8_t>(row.envelope));write(b,static_cast<uint8_t>(row.crossed));write(b,row.limit);}
}
} // namespace hardcore::simulation::crowd
