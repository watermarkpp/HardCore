#include "pursuit_numeric.h"
#include "crowd_geometry_kernel.h"
#include <algorithm>
#include <cmath>
#include <limits>

#if defined(__FAST_MATH__) || defined(_M_FP_FAST)
#error Pursuit requires pinned precise Vector2/scalar arithmetic
#endif
namespace hardcore::simulation::pursuit {
static double sq(double v) { return v * v; }
static Vector2i cell(Vector2 p) { return Vector2i(int(std::floor(p.x)), int(std::floor(p.y))); }
static Vector2i bucket(Vector2 p) { return Vector2i(int(std::floor(p.x / 8.0)), int(std::floor(p.y / 8.0))); }
static Vector2 center(Vector2i p) { return Vector2(p.x + 0.5, p.y + 0.5); }
static const Vector2i neighbors[] = {{-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1}};
static const Vector2 directions[] = {{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,1},{-1,-1},{1,-1}};
static double clamp(double v, double a, double b) { return std::max(a, std::min(b, v)); }
static double cross(Vector2 a, Vector2 b) { return a.cross(b); }
static double distance(Vector2 a, Vector2 b) { return a.distance_to(b); }
static double segment_distance(Vector2 p, Vector2 a, Vector2 b) {
    Vector2 d = b - a; double len = d.length_squared();
    return len <= sq(GEO_EPS) ? p.distance_squared_to(a) : p.distance_squared_to(a + d * clamp((p-a).dot(d)/len, 0, 1));
}
static Vector2 nearest(Vector2 p, Vector2 a, Vector2 b) {
    Vector2 d = b-a; return d.length_squared() <= sq(GEO_EPS) ? a : a+d*clamp((p-a).dot(d)/d.length_squared(),0,1);
}
static bool touch(Vector2 a, Vector2 b, Vector2 c, Vector2 d) {
    double x=cross(b-a,c-a), y=cross(b-a,d-a), z=cross(d-c,a-c), w=cross(d-c,b-c);
    if (((x>GEO_EPS && y<-GEO_EPS)||(x<-GEO_EPS && y>GEO_EPS)) && ((z>GEO_EPS && w<-GEO_EPS)||(z<-GEO_EPS && w>GEO_EPS))) return true;
    return (std::abs(x)<=GEO_EPS && segment_distance(c,a,b)<=sq(GEO_EPS)) || (std::abs(y)<=GEO_EPS && segment_distance(d,a,b)<=sq(GEO_EPS)) || (std::abs(z)<=GEO_EPS && segment_distance(a,c,d)<=sq(GEO_EPS)) || (std::abs(w)<=GEO_EPS && segment_distance(b,c,d)<=sq(GEO_EPS));
}
// Pinned Geometry2D::segment_intersects_segment, operands and real_t retained.
static bool intersect(Vector2 from_a, Vector2 to_a, Vector2 from_b, Vector2 to_b, Vector2 *out) {
    Vector2 B=to_a-from_a, C=from_b-from_a, D=to_b-from_a;
    real_t ABlen=B.dot(B); if (ABlen<=0) return false;
    Vector2 Bn=B/ABlen;
    C=Vector2(C.x*Bn.x+C.y*Bn.y,C.y*Bn.x-C.x*Bn.y);
    D=Vector2(D.x*Bn.x+D.y*Bn.y,D.y*Bn.x-D.x*Bn.y);
    if ((C.y<(real_t)-CMP_EPSILON && D.y<(real_t)-CMP_EPSILON)||(C.y>(real_t)CMP_EPSILON && D.y>(real_t)CMP_EPSILON)) return false;
    if (Math::is_equal_approx(C.y,D.y)) return false;
    real_t ABpos=D.x+(C.x-D.x)*D.y/(D.y-C.y);
    if (ABpos<0 || ABpos>1) return false;
    if (out) *out=from_a+B*ABpos;
    return true;
}
bool point_in_polygon(Vector2 p, const Polygon &polygon) {
    if (polygon.size()<3) return false;
    Vector2 away(-1e20,-1e20), opposite(1e20,1e20);
    for (const Vector2 &v:polygon) { away=away.max(v); opposite=opposite.min(v); }
    away+=(away-opposite)*Vector2(1.221313,1.512312);
    int intersections=0;
    for (size_t i=0;i<polygon.size();++i) {
        Vector2 res;
        if (intersect(polygon[i],polygon[(i+1)%polygon.size()],p,away,&res)) {
            ++intersections; if (res.is_equal_approx(p)) return true;
        }
    }
    return intersections&1;
}
bool capsule_hits_polygon(Vector2 a, Vector2 b, double radius, const Polygon &p) {
    if (point_in_polygon(a,p)||point_in_polygon(b,p)) return true;
    double inner=std::max(0.0,radius-GEO_EPS);
    for (size_t i=0;i<p.size();++i) {
        Vector2 c=p[i],d=p[(i+1)%p.size()];
        if (touch(a,b,c,d)) return true;
        double sep=std::min(std::min(segment_distance(a,c,d),segment_distance(b,c,d)),std::min(segment_distance(c,a,b),segment_distance(d,a,b)));
        if (radius>0 && sep<inner*inner) return true;
    }
    return false;
}
bool Navigation::inside(Vector2 p,double r) const {
    return p.is_finite() && std::isfinite(r) && r>=0 && p.x-r>=-GEO_EPS && p.y-r>=-GEO_EPS && p.x+r<=design_size.x+GEO_EPS && p.y+r<=design_size.y+GEO_EPS;
}
bool Navigation::capsule_blocked(Vector2 a,Vector2 b,double r) const {
    if (!inside(a,r)||!inside(b,r)) return true;
    if (!polygon) {
        // Legacy point_walkable uses the floored cell centre and footprint.
        // Direct segment legality stays the original S terrain/WORLD repair.
        return !cell_walkable(cell(a),r)||!cell_walkable(cell(b),r);
    }
    // Rect2 methods take real_t, unlike scalar radius comparisons. Preserve
    // the original expand/grow operand conversions and end accumulation.
    Rect2 box=Rect2(a,Vector2()).expand(b).grow(real_t(r));
    Vector2 first_point=box.position-Vector2(GEO_EPS,GEO_EPS), last_point=box.get_end()+Vector2(GEO_EPS,GEO_EPS);
    Rect2 padded=box.grow(real_t(GEO_EPS));
    Vector2i first=bucket(first_point),last=bucket(last_point);
    for (int y=first.y;y<=last.y;++y) for (int x=first.x;x<=last.x;++x) {
        auto entry=part_buckets.find({x,y}); if (entry==part_buckets.end()) continue;
        for (int id:entry->second) {
            Vector2i owner=first_buckets[id];
            if (x!=std::max(first.x,owner.x)||y!=std::max(first.y,owner.y)) continue;
            if (!padded_bounds[id].intersects(padded,true)) continue;
            if (capsule_hits_polygon(a,b,r,parts[id])) return true;
        }
    }
    return false;
}
bool Navigation::cell_walkable(Vector2i c,double r) const {
    if (c.x<0||c.y<0||c.x>=design_size.x||c.y>=design_size.y) return false;
    Vector2 p=center(c); if (polygon) return !capsule_blocked(p,p,r);
    if (blocked_cells.count(c)) return false;
    r=std::max(0.0,r);
    if (p.x-r<0||p.y-r<0||p.x+r>design_size.x||p.y+r>design_size.y) return false;
    if (r<=0) return true;
    int count=int(std::ceil(r+0.5));
    for (int y=-count;y<=count;++y) for (int x=-count;x<=count;++x) {
        Vector2i b=c+Vector2i(x,y); if (!blocked_cells.count(b)) continue;
        Vector2 delta=(p-center(b)).abs()-Vector2(0.5,0.5);
        double length=Vector2(std::max(0.0,double(delta.x)),std::max(0.0,double(delta.y))).length();
        if (length+GEO_EPS<r) return false;
    }
    return true;
}
bool Navigation::neighbor_clear(Vector2i a,Vector2i b,double r) const {
    Vector2i d=b-a; if (d==Vector2i()||std::abs(d.x)>1||std::abs(d.y)>1) return false;
    if (polygon) return !capsule_blocked(center(a),center(b),r);
    return cell_walkable(b,r) && (d.x==0||d.y==0||(cell_walkable(a+Vector2i(d.x,0),r)&&cell_walkable(a+Vector2i(0,d.y),r)));
}
Attachment Navigation::attach(Vector2 p,double r) const {
    if (capsule_blocked(p,p,r)) return {};
    auto at=face_buckets.find(bucket(p));
    if (at!=face_buckets.end()) for (int id:at->second) if (point_in_polygon(p,faces[id])) return {id,p};
    Vector2i first=bucket(p-Vector2(0.20,0.20)),last=bucket(p+Vector2(0.20,0.20));
    std::set<int> seen; double best=0.20*0.20; Attachment result;
    for (int y=first.y;y<=last.y;++y) for (int x=first.x;x<=last.x;++x) {
        auto entry=face_buckets.find({x,y}); if (entry==face_buckets.end()) continue;
        for (int id:entry->second) {
            if (!seen.insert(id).second) continue;
            const auto &pgn=faces[id];
            for (size_t i=0;i<pgn.size();++i) {
                Vector2 n=nearest(p,pgn[i],pgn[(i+1)%pgn.size()]); double dist=p.distance_squared_to(n);
                if (dist<best&&!capsule_blocked(p,n,r)) { best=dist; result={id,n}; }
            }
        }
    }
    return result;
}
bool FrozenWorld::point_allowed(Vector2 p,double r) const {
    for (const auto &zone:safe_zone_polygons) if (point_in_polygon(p,zone)) return false;
    for (const auto &zone:safe_zone_circles) if (distance(p,zone.first)<=zone.second+GU_EPS) return false;
    for (const auto &part:world_parts) if (capsule_hits_polygon(p,p,r,part)) return false;
    return true;
}
bool FrozenWorld::segment_clear(Vector2 a,Vector2 b) const {
    for (const auto &part:world_parts) if (capsule_hits_polygon(a,b,0,part)) return false;
    return true;
}
Vector2 next_source_leg(Vector2 p,Vector2 w,double budget) {
    Vector2 d=w-p;
    double sx=std::abs(double(d.x))<=GU_EPS?0:(d.x>0?1:-1), sy=std::abs(double(d.y))<=GU_EPS?0:(d.y>0?1:-1);
    if (sx && sy) return p+Vector2(sx,sy)*std::min(budget,std::min(std::abs(double(d.x)),std::abs(double(d.y))));
    if (sx) return p+Vector2(sx*std::min(std::abs(double(d.x)),budget),0);
    if (sy) return p+Vector2(0,sy*std::min(std::abs(double(d.y)),budget));
    return w;
}
static bool edge_less(const std::pair<Vector2i,Vector2i> &a,const std::pair<Vector2i,Vector2i> &b) {
    CellLess less; return a.first!=b.first?less(a.first,b.first):less(a.second,b.second);
}
Actor::Actor():failed_edges(edge_less) {}
Search::Search(std::shared_ptr<const Navigation> n,std::shared_ptr<const FrozenWorld> w,Actor a,std::shared_ptr<const std::vector<Peer>> p):nav_(std::move(n)),world_(std::move(w)),peers_(std::move(p)),actor_(std::move(a)) {
    output_.id=actor_.id; output_.life=actor_.life; output_.status="SEARCHING";
    victim_anchor_=actor_.target;
    if (!nav_||!world_||!peers_||!actor_.position.is_finite()||!actor_.target.is_finite()||!std::isfinite(actor_.radius)||actor_.radius<0) finish("INVALID_CONTEXT");
}
bool Search::Less::operator()(const Item &a,const Item &b) const {
    if (a.f!=b.f) return a.f>b.f;
    if (a.g!=b.g) return a.g>b.g;
    if (a.face>=0 || b.face>=0) return a.face>b.face;
    return a.cell.y!=b.cell.y?a.cell.y>b.cell.y:a.cell.x>b.cell.x;
}
void Search::finish(const char *s) { output_.status=s; phase_=Phase::DONE; }
bool Search::point_allowed(Vector2 p) {
    ++output_.numeric_checks; return !nav_->capsule_blocked(p,p,actor_.radius)&&world_->point_allowed(p,actor_.radius);
}
bool Search::destination_clear(Vector2 p) {
    for (const Peer &other:*peers_) {
        if (other.id==actor_.id||other.id==actor_.target_id||!other.enemy) continue;
        ++output_.numeric_checks;
        double r=std::max(0.0,actor_.radius+other.radius);
        if (!(p.distance_squared_to(other.position)>=r*r-GU_EPS) && other.damage_eligible && other.world_collision) return false;
    }
    return true;
}
bool Search::motion_clear(Vector2 a,Vector2 b) {
    if (output_.surround_present && crowd::core_crossed(a,b,victim_anchor_,actor_.radius,actor_.target_radius,GU_EPS)) return false;
    for (const Peer &other:*peers_) {
        if (other.id==actor_.id||other.id==actor_.target_id||!other.enemy||!other.damage_eligible||!other.world_collision) continue;
        ++output_.numeric_checks;
        if (crowd::core_crossed(a,b,other.position,actor_.radius,other.radius,GU_EPS)) return false;
    }
    return true;
}
bool Search::edge_clear(Vector2i a,Vector2i b) const { return !actor_.failed_edges.count({a,b}); }
void Search::station_one() {
    // Current ordinary _hc_tick_melee deliberately does not call the ideal
    // station chooser. Retain only an already admitted source detour.
    if (actor_.surround_present) { output_.surround_present=true; output_.surround=actor_.surround; output_.surround_slot=actor_.surround_slot; actor_.target=actor_.surround; }
    if (actor_.flank_present) { output_.flank_present=true; output_.flank=actor_.flank; output_.route={actor_.flank}; finish("FOUND"); return; }
    if (actor_.route_index<actor_.retained_route.size()) { output_.route.assign(actor_.retained_route.begin()+actor_.route_index,actor_.retained_route.end()); finish("FOUND"); return; }
    Vector2 leg=next_source_leg(actor_.position,actor_.target);
    bool body=motion_clear(actor_.position,leg);
    if (body && !nav_->capsule_blocked(actor_.position,leg,actor_.radius) && edge_clear(cell(actor_.position),cell(leg)) && point_allowed(leg)) {
        output_.route={actor_.target}; finish("FOUND"); return;
    }
    if (!body || frontline(actor_.position)) {
        if (!actor_.side_retry_due) { finish("FRONTLINE_BLOCKED"); return; }
        Vector2 delta=actor_.position-victim_anchor_; far_approach_=!output_.surround_present && std::max(std::abs(double(delta.x)),std::abs(double(delta.y)))>1.0+actor_.radius*2.0;
        phase_=Phase::FLANK; return;
    }
    phase_=Phase::GOALS;
}
bool Search::frontline(Vector2 a) const {
    double d=distance(a,victim_anchor_);
    for (const Peer &other:*peers_) {
        if (!other.enemy||!other.damage_eligible||!other.world_collision||other.id==actor_.id||other.id==actor_.target_id) continue;
        Vector2 b=other.position; bool overlap=a.distance_squared_to(b)<=sq(actor_.radius+other.radius);
        double da=b.distance_squared_to(victim_anchor_),db=a.distance_squared_to(victim_anchor_);
        bool before=da<db||(da==db&&other.stable_order<actor_.stable_order);
        if (overlap&&!before) continue;
        if (d<=GU_EPS) { if (overlap&&before) return true; continue; }
        Vector2 u=(victim_anchor_-a)/d; double along=(b-a).dot(u);
        if (!overlap&&(along<=GU_EPS||along>=d-GU_EPS)) continue;
        if (overlap&&(along<-GU_EPS||along>=d+GU_EPS)) continue;
        Vector2 s=a+u*std::max(0.0,actor_.radius),e=victim_anchor_-u*std::max(0.0,actor_.target_radius);
        if ((e-s).dot(u)<=GU_EPS||overlap) { s=a; e=victim_anchor_; }
        if (segment_distance(b,s,e)<=sq(std::max(0.0,other.radius)+0.10+GU_EPS)) return true;
    }
    return false;
}
void Search::flank_one() {
    if (station_index_>=size_t(far_approach_?7:8)) {
        if (output_.flank_present) { output_.route={output_.flank}; finish("FOUND"); } else { station_index_=0; phase_=Phase::CONTACT; } return;
    }
    Vector2i option;
    double sign=(actor_.id%2==0)?1.0:-1.0;
    if (far_approach_) {
        static const Vector2i headings[]={{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}};
        static const int sides[]={1,-1,2,-2,3,-3,4};
        Vector2 delta=actor_.target-actor_.position; double ax=std::abs(double(delta.x)),ay=std::abs(double(delta.y));
        Vector2i direct(delta.x>0?1:-1,delta.y>0?1:-1);
        if (ay<=ax*0.41421356237309503) direct.y=0; else if (ax<=ay*0.41421356237309503) direct.x=0;
        int heading=-1; for (int i=0;i<8;++i) if (headings[i]==direct) heading=i;
        if (heading<0) { station_index_=7; return; }
        option=headings[(heading+sides[station_index_++]*int(sign)+16)%8];
    } else option=neighbors[station_index_++];
    Vector2 endpoint=center(cell(actor_.position)+option),leg=next_source_leg(actor_.position,endpoint);
    if (output_.surround_present && endpoint.distance_squared_to(victim_anchor_)<sq(actor_.radius+actor_.target_radius)) return;
    if (nav_->capsule_blocked(actor_.position,leg,actor_.radius)||!edge_clear(cell(actor_.position),cell(leg))||!point_allowed(leg)||!point_allowed(endpoint)||!motion_clear(actor_.position,leg)||!destination_clear(endpoint)) return;
    // Original far chooser also checks the complete waypoint chord.
    if (far_approach_&&!motion_clear(actor_.position,endpoint)) return;
    double cost=distance(endpoint,actor_.target)+(Vector2(option).cross(actor_.target-actor_.position)*sign<0?0.05:0);
    if (!far_approach_&&frontline(endpoint)) cost+=2.0;
    if (far_approach_||cost<station_cost_) { station_cost_=cost; output_.flank_present=true; output_.flank=endpoint; if (far_approach_) { output_.route={endpoint}; finish("FOUND"); } }
}
void Search::contact_one() {
    if (station_index_>=8) { if (output_.flank_present) { output_.route={output_.flank}; finish("FOUND"); } else finish("FRONTLINE_BLOCKED"); return; }
    Vector2 direction(neighbors[station_index_++]); double extent=1.0;
    for (const Peer &other:*peers_) {
        if (other.id==actor_.id||other.id==actor_.target_id||!other.enemy||!other.damage_eligible||!other.world_collision) continue;
        double r=actor_.radius+other.radius+actor_.margin+other.margin; Vector2 d=other.position-actor_.position;
        if (std::max(std::abs(double(d.x)),std::abs(double(d.y)))>1.0+r) continue;
        extent=crowd::free_ray_extent(actor_.position,direction,other.position,r,extent,GU_EPS);
    }
    extent=crowd::free_ray_extent(actor_.position,direction,victim_anchor_,actor_.radius+actor_.target_radius+actor_.margin+actor_.target_margin,extent,GU_EPS);
    if (extent<=GU_EPS) return;
    Vector2 p=actor_.position+direction*extent;
    if (!motion_clear(actor_.position,p)||nav_->capsule_blocked(actor_.position,p,actor_.radius)||!edge_clear(cell(actor_.position),cell(p))||!point_allowed(p)) return;
    double sign=actor_.id%2==0?1.0:-1.0;
    double cost=distance(p,actor_.target)+(direction.cross(actor_.target-actor_.position)*sign<0?0.05:0);
    bool rear=output_.surround_slot<0; if (!rear&&frontline(p)) cost+=2.0;
    double length=actor_.position.distance_squared_to(p);
    if ((rear&&length>best_extent_)||((!rear||length==best_extent_)&&cost<station_cost_)) { station_cost_=cost; best_extent_=length; output_.flank_present=true; output_.flank=p; }
}
void Search::goal_one() {
    if (output_.surround_present) {
        if (point_allowed(actor_.target)) goals_.push_back({cell(actor_.target),actor_.target,{}});
        phase_=Phase::ATTACH_START; return;
    }
    // Original _hc_goal_points: HCPolicy.START_GU=1.5 => ceil+1=3;
    // ordinary source176 samples L-inf <=1.0+epsilon plus the eight box points.
    if (sample_index_>=57) { phase_=Phase::ATTACH_START; return; }
    size_t sample=sample_index_++; Vector2 p; Vector2i c;
    if (sample<49) { c=cell(actor_.target)+Vector2i(int(sample%7)-3,int(sample/7)-3); p=center(c); }
    else { static const Vector2 offsets[]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}; p=actor_.target+offsets[sample-49]; c=cell(p); }
    Vector2 offset=p-actor_.target; double extent=std::max(std::abs(double(offset.x)),std::abs(double(offset.y)));
    if (sample<49 && !(extent>GU_EPS && extent<=1.0+GU_EPS)) return;
    for (const auto &g:goals_) if (g.cell==c) return;
    if (distance(p,actor_.target)<actor_.radius+actor_.target_radius||!point_allowed(p)||!world_->segment_clear(p,actor_.target)) return;
    goals_.push_back({c,p,{}});
}
double Search::heuristic(int face) const {
    double best=std::numeric_limits<double>::infinity(); for (const auto &g:goals_) if (g.attachment.valid()) best=std::min(best,distance(nav_->centers[face],g.goal)); return best;
}
double Search::grid_heuristic(Vector2i c) const {
    double best=std::numeric_limits<double>::infinity(); for (const auto &g:goals_) { int dx=std::abs(g.cell.x-c.x),dy=std::abs(g.cell.y-c.y); best=std::min(best,double(std::max(dx,dy))+(1.4142135623730951-1.0)*double(std::min(dx,dy))); } return best;
}
void Search::attach_goal_one() {
    if (goal_index_<goals_.size()) { auto &g=goals_[goal_index_++]; g.attachment=nav_->attach(g.goal,actor_.radius); return; }
    goals_.erase(std::remove_if(goals_.begin(),goals_.end(),[](const Goal &g){return !g.attachment.valid();}),goals_.end());
    if (goals_.empty()) { finish("NO_VALID_GOAL_IN_CURRENT_SAMPLE"); return; }
    double score=distance(actor_.position,start_.point)+distance(start_.point,nav_->centers[start_.face]);
    scores_[start_.face]=score; heap_.push({score+heuristic(start_.face),score,start_.face,{}}); phase_=Phase::SEARCH;
}
void Search::search_one() {
    if (nav_->polygon && best_goal_>=0 && (heap_.empty()||heap_.top().f>=best_cost_-GEO_EPS)) { cursor_=goals_[best_goal_].attachment.face; phase_=Phase::RECONSTRUCT; return; }
    if (heap_.empty()) { finish("NO_ROUTE_FOR_CURRENT_GRAPH"); return; }
    Item item=heap_.top(); heap_.pop();
    if (nav_->polygon) {
        int face=item.face; if (closed_.count(face)||item.g>scores_[face]+GEO_EPS) return;
        closed_.insert(face); ++output_.expansions;
        for (size_t i=0;i<goals_.size();++i) if (goals_[i].attachment.face==face) {
            const Goal &g=goals_[i]; double total=scores_[face]+distance(nav_->centers[face],g.attachment.point)+distance(g.attachment.point,g.goal);
            if (total<best_cost_) { best_cost_=total; best_goal_=int(i); }
        }
        for (const Link &link:nav_->links[face]) {
            if (closed_.count(link.to)) continue;
            double score=scores_[face]+link.cost; auto prev=scores_.find(link.to);
            if (prev!=scores_.end() && score>=prev->second-GEO_EPS) continue;
            if (prev==scores_.end() && scores_.size()>=8192) { finish("SEARCH_CAPACITY_LIMIT"); return; }
            scores_[link.to]=score; parents_[link.to]={face,link.portal}; heap_.push({score+heuristic(link.to),score,link.to,{}});
        }
    } else {
        Vector2i c=item.cell; if (grid_closed_.count(c)||item.g>grid_scores_[c]+GEO_EPS) return;
        for (size_t i=0;i<goals_.size();++i) if (goals_[i].cell==c) { best_goal_=int(i); grid_cursor_=c; grid_reconstructing_=true; phase_=Phase::RECONSTRUCT; return; }
        grid_closed_.insert(c); ++output_.expansions;
        for (const Vector2i &step:neighbors) {
            Vector2i next=c+step; if (grid_closed_.count(next)||!nav_->neighbor_clear(c,next,actor_.radius)||!edge_clear(c,next)) continue;
            double score=grid_scores_[c]+(step.x && step.y?1.4142135623730951:1.0); auto prev=grid_scores_.find(next);
            if (prev!=grid_scores_.end() && score>=prev->second-GEO_EPS) continue;
            if (prev==grid_scores_.end() && grid_scores_.size()>=8192) { finish("SEARCH_CAPACITY_LIMIT"); return; }
            grid_scores_[next]=score; grid_parents_[next]=c; heap_.push({score+grid_heuristic(next),score,-1,next});
        }
    }
}
void Search::reconstruct_one() {
    if (grid_reconstructing_) {
        if (grid_cursor_!=cell(actor_.position)) {
            if (raw_path_.size()>8192||!grid_parents_.count(grid_cursor_)) { finish("INVALID_PARENT_CHAIN"); return; }
            raw_path_.push_back(center(grid_cursor_)); grid_cursor_=grid_parents_[grid_cursor_]; return;
        }
        std::reverse(raw_path_.begin(),raw_path_.end());
        if (raw_path_.empty()) raw_path_.push_back(goals_[best_goal_].goal); else raw_path_.back()=goals_[best_goal_].goal;
        output_.route=raw_path_; finish("FOUND"); return;
    }
    if (reverse_faces_.size()>8192) { finish("INVALID_PARENT_CHAIN"); return; }
    reverse_faces_.push_back(cursor_);
    if (cursor_==start_.face) { face_chain_=reverse_faces_; std::reverse(face_chain_.begin(),face_chain_.end()); raw_path_.push_back(start_.point); raw_path_.push_back(nav_->centers[face_chain_[0]]); phase_=Phase::ASSEMBLE; return; }
    auto parent=parents_.find(cursor_); if (parent==parents_.end()) { finish("INVALID_PARENT_CHAIN"); return; } cursor_=parent->second.first;
}
void Search::assemble_one() {
    if (assemble_index_<int(face_chain_.size())) { int face=face_chain_[assemble_index_++]; raw_path_.push_back(parents_[face].second); raw_path_.push_back(nav_->centers[face]); return; }
    const Goal &g=goals_[best_goal_]; raw_path_.push_back(g.attachment.point); raw_path_.push_back(g.goal); smooth_anchor_=actor_.position; phase_=Phase::SMOOTH;
}
void Search::smooth_one() {
    if (smooth_index_>=int(raw_path_.size())) { finish("FOUND"); return; }
    if (smooth_anchor_.distance_squared_to(raw_path_[smooth_index_])<=sq(GEO_EPS)) { ++smooth_index_; smooth_probe_=-1; return; }
    if (smooth_probe_<smooth_index_) smooth_probe_=std::min(int(raw_path_.size())-1,smooth_index_+8);
    Vector2 candidate=raw_path_[smooth_probe_];
    if (!nav_->capsule_blocked(smooth_anchor_,candidate,actor_.radius)) { output_.route.push_back(candidate); smooth_anchor_=candidate; smooth_index_=smooth_probe_+1; smooth_probe_=-1; return; }
    if (smooth_probe_==smooth_index_) { output_.route.clear(); finish("POLYGON_ROUTE_CLEARANCE_FAILED"); return; } --smooth_probe_;
}
bool Search::advance(uint32_t limit) {
    ++output_.slices;
    for (uint32_t work=0;work<std::max(1u,limit)&&phase_!=Phase::DONE;++work) {
        ++output_.work_units;
        switch (phase_) {
            case Phase::STATION: station_one(); break;
            case Phase::FLANK: flank_one(); break;
            case Phase::CONTACT: contact_one(); break;
            case Phase::GOALS: goal_one(); break;
            case Phase::ATTACH_START:
                if (goals_.empty()) { finish("NO_VALID_GOAL_IN_CURRENT_SAMPLE"); break; }
                if (nav_->polygon) { start_=nav_->attach(actor_.position,actor_.radius); if (!start_.valid()) finish("NO_ROUTE_FOR_CURRENT_GRAPH"); else phase_=Phase::ATTACH_GOALS; }
                else { Vector2i start=cell(actor_.position); grid_scores_[start]=0; heap_.push({grid_heuristic(start),0,-1,start}); phase_=Phase::SEARCH; }
                break;
            case Phase::ATTACH_GOALS: attach_goal_one(); break;
            case Phase::SEARCH: search_one(); break;
            case Phase::RECONSTRUCT: reconstruct_one(); break;
            case Phase::ASSEMBLE: assemble_one(); break;
            case Phase::SMOOTH: smooth_one(); break;
            case Phase::DONE: break;
        }
    }
    return phase_==Phase::DONE;
}
} // namespace hardcore::simulation::pursuit
